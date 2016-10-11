import os
import re
import tables
import numpy as np
import pandas as pd
import parse

known_specs = [
    {
        'file_pattern': '{location_id}_{year_id}_{sex_id}.h5',
        'h5_tablename': 'draws'},
    {
        'file_pattern': '{measure_id}_{location_id}_{year_id}_{sex_id}.csv'},
    {
        'file_pattern': 'all_draws.h5',
        'h5_tablename': 'draws'}]


class InvalidSpec(Exception):
    pass


class InvalidFilter(Exception):
    pass


class SuperGopher(object):
    """Flexible finder, reader, filterer, and retreiver of GBD file
    contents based on a minimal naming convention specification.

    After initializing a SuperGopher with a spec and directory, the user
    will typically inteface with one function - SuperGopher.content()
    """

    def __init__(self, spec, directory):
        """Inititial a FlexFinder for a given file spec and directory.

        Args:
            spec (dict): A dictionary giving some information about the
                file naming conventions in the directory. Minimally,
                the key "file_pattern" must have a string value where
                variables in filenames are enclosed in {}. For example,
                if specific location_id-sex_id combinations are stored
                in separate files, the spec might look something like...

                    spec={'file_pattern': '{location_id}_{sex_id}.csv'}

                If the files are stored as h5s, one additional key-value
                pair is required, h5_tablename-my_table_name. For
                example,

                    spec={
                        'file_pattern': '{location_id}_{sex_id}.csv',
                        'h5_tablename': 'draws'}

            directory (str): The directory where files matching the
                spec are stored
        """

        self.spec = spec
        self.directory = directory

        # Require that at least one file matches the file_pattern
        self.all_files = os.listdir(self.directory)
        self.all_files = self._id_files()
        if not len(self.all_files) > 0:
            raise InvalidSpec(
                "There are no files in the given directory that match the "
                "provided file_pattern")

        # Require an h5_tablename is provided for hdfs
        self.extension = self.spec['file_pattern'].split(".")[-1]
        if self.extension.lower() == 'h5':
            if 'h5_tablename' not in self.spec.keys():
                raise InvalidSpec(
                    "Must provide the 'h5_tablename' if "
                    "the file format is hdf")
            if self.spec['h5_tablename'] is None:
                raise InvalidSpec(
                    "'h5_tablename' cannot be None if the file format is hdf")
            self.h5_tablename = self.spec['h5_tablename']
            self.h5_indexes = self.get_index_cols(self.all_files[0])
        elif self.extension.lower() == 'csv':
            self.h5_tablename = ''
            self.h5_indexes = []
        else:
            raise InvalidSpec(
                "Only csv and h5 files are supported at this time")

        self.file_columns = self.get_non_index_cols(self.all_files[0])
        if self.extension.lower() == 'h5':
            self.index_cols = self.get_index_cols(self.all_files[0])

    def get_index_cols(self, h5_file):
        """Get the index_cols of the h5_file (i.e. the "data_columns"
        if saved using Pandas DataFrame.to_hdf())"""
        f = tables.open_file('%s/%s' % (self.directory, h5_file), mode='r')
        index_cols = f.getNode(
            '/%s' % self.h5_tablename).table.colindexes.keys()
        f.close()
        index_cols = list(set(index_cols) - set(['index']))
        return index_cols

    def get_index_col_levels(self, index_col):
        """Get the unique levels of the given index_col"""
        for f in self.all_files:
            f = tables.open_file('%s/%s' % (self.directory, f), mode='r')
            index_lvls = set(
                f.getNode('/%s' % self.spec['h5_tablename']).table.colindexes[
                    index_col].read_sorted())
            f.close()
        return index_lvls

    def get_non_index_cols(self, f):
        """Return all column names that aren't included in the index"""
        if self.extension.lower() == 'h5':
            file_columns = list(pd.read_hdf(
                    '%s/%s' % (self.directory, f),
                    self.spec['h5_tablename'], start=0, stop=1).columns)
        elif self.extension.lower() == 'csv':
            file_columns = list(pd.read_csv(
                '%s/%s' % (self.directory, f), nrows=1).columns)
        else:
            file_columns = None
        return file_columns

    def file_filter_keys(self):
        """Return the variables by which files themselves are
        filterable"""
        return re.findall('{(.*?)}', self.spec['file_pattern'])

    def _refresh_all_files(self):
        self.all_files = os.listdir(self.directory)
        self.all_files = self._id_files()

    def _id_files(self, **kwargs):
        """Identify the files matching the given kwargs filters"""
        fmt_dict = {}
        ffks = self.file_filter_keys()
        for filter_key, filter_values in kwargs.iteritems():
            if filter_key in ffks:
                filter_values = [
                    str(fv) for fv in np.atleast_1d(filter_values)]
                fmt_dict[filter_key] = '(%s)' % "|".join(filter_values)
                ffks.remove(filter_key)
        for ffk in ffks:
            fmt_dict[ffk] = '.*'
        fre = self.spec['file_pattern'].format(**fmt_dict)
        fre = '^%s' % fre
        files = [f for f in self.all_files
                 if re.search(fre, f) is not None]
        return files

    def _add_missing_cols(self, df, f):
        fn_parsed = parse.parse(self.spec['file_pattern'], f).named
        for k in fn_parsed.keys():
            if k not in df.columns:
                df[k] = fn_parsed[k]
        return df

    def _read_files(self, files, where, **kwargs):
        """Return a dataframe with the contents of 'files' that match the
        'where' clause"""
        df = []
        for f in files:
            if self.extension.lower() == 'h5':
                if len(where) > 0:
                    thisdf = pd.read_hdf(
                        '%s/%s' % (self.directory, f),
                        self.spec['h5_tablename'], where=where)
                    thisdf = self._add_missing_cols(thisdf, f)
                    df.append(thisdf)
                else:
                    thisdf = pd.read_hdf(
                        '%s/%s' % (self.directory, f),
                        self.spec['h5_tablename'])
                    thisdf = self._add_missing_cols(thisdf, f)
                    df.append(thisdf)
            elif self.extension.lower() == 'csv':
                thisdf = pd.read_csv('%s/%s' % (self.directory, f))
                thisdf = self._add_missing_cols(thisdf, f)
                df.append(thisdf)
        if len(df) == 0:
            raise InvalidFilter("Filter does not match any files in directory")
        else:
            return pd.concat(df)

    def _create_where_clause(self, **kwargs):
        where = []
        for filter_key, filter_values in kwargs.iteritems():
            if isinstance(filter_values, (list, set)):
                filter_values = [str(fv) for fv in filter_values]
                where.append("{fk} in [{fvs}]".format(
                    fk=filter_key, fvs=",".join(filter_values)))
            else:
                where.append("{fk} == {fv}".format(
                    fk=filter_key, fv=filter_values))
        return " & ".join(where)

    def _create_post_filter(self, **kwargs):
        wkwargs = {k: v for k, v in kwargs.iteritems()
                   if k not in self.file_filter_keys() and
                   (k not in self.h5_indexes or
                    len(np.atleast_1d(v)) > 20)}
        return self._create_where_clause(**wkwargs)

    def _create_hdf_filter(self, **kwargs):
        wkwargs = {k: v for k, v in kwargs.iteritems()
                   if k not in self.file_filter_keys() and
                   k in self.h5_indexes and
                   len(np.atleast_1d(v)) <= 20}
        return self._create_where_clause(**wkwargs)

    def _invalid_filter_keys(self, **kwargs):
        available_filters = (
                self.file_filter_keys() + self.h5_indexes + self.file_columns)
        invalid_keys = set(kwargs.keys()) - set(available_filters)
        return list(invalid_keys)

    def content(self, **kwargs):
        """The magic function for this class, returns a DataFrame of
        all file contents matching the filter_variable=filter_value
        criteria. For example, if you wanted to retreive all content for
        location_id=6 and age_group_ids 22 and 27, you would call:

            superGopherInstance.content(
                location_id=6, age_group_id=[22, 27])

        If no filters are specified, this will retrieve ALL content
        contained in the spec-matched files in the SuperGopher
        directory. This could be a lot of content... so be careful or
        you could run out of memory or end up waiting a very long
        time.

        Args:
            **kwargs: A set of kwarg=value pairs where the kwargs is
                the variable (i.e. part of a filename, and hdf index,
                or column in the the stored tables) to filter on
                and value is either a list, string, or integer that the
                variable should match. Only exact equality
                or "IN" logic for lists is supported for filtering.

        Returns:
            A DataFrame with content matching the provided filters
        """
        invalid_keys = self._invalid_filter_keys(**kwargs)
        if len(invalid_keys) != 0:
            raise InvalidFilter(
                    "Keys not found in filename patterns, h5_indexes, "
                    "or file column names: %s" % (", ".join(invalid_keys)))

        self._refresh_all_files()
        files_to_read = self._id_files(**kwargs)
        hdf_filter = self._create_hdf_filter(**kwargs)
        post_filter = self._create_post_filter(**kwargs)

        df = self._read_files(files_to_read, hdf_filter, **kwargs)
        if len(post_filter) > 0:
            df = df.query(post_filter)
        df = df.reset_index(drop=True)
        df = self.cast_id_cols(df)
        return df

    def cast_id_cols(self, df):
        dfc = df.copy()
        id_cols = [c for c in dfc if '_id' in c]
        for ic in id_cols:
            try:
                dfc[ic] = dfc[ic].astype('int')
            except:
                pass
        return dfc

    @classmethod
    def auto(cls, directory):
        sgs = []
        for s in known_specs:
            try:
                sgs.append(cls(s, directory))
            except InvalidSpec:
                pass
        assert len(sgs) > 0, (
            "Could not find files matching any known file specs in %s" %
            (directory))
        assert len(sgs) == 1, (
            "%s More than one matching spec was found in %s" %
            (directory))
        return sgs[0]
