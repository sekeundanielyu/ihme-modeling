# Utilities for interoperating with stata. In particular, functions for
# exporting dataframes as a DCT format.
import sys


def to_dct(df, fname, include_header):
    ''' Take a pandas dataframe and write a stata .dct file.
    Stata can read these about 10x faster than csvs.

    Example data format:
    infile dictionary {
    str50 foo
    double bar
    }
    baz 1.01
    qux 2.01

    Arguments:
        df: dataframe to write
        fname: file to write to (could be stdout)
        include_header: boolean, should be true for first dataset and
            false for all others

    Returns:
        None
    '''
    if include_header:
        write_header(df, fname)
    df.fillna('.').to_csv(fname, mode='a', index=False, header=False, sep=" ")


def write_header(df, fname):
    '''write a stata infile dictionary header to a given file

    Arguments:
        df: dataframe to inspect to get column info
        fname: file to write to (could be stdout)

    Returns:
        None
    '''
    # get column name and pandas dtype info
    raw_dtypes = ((col, dt) for (col, dt) in
                  zip(df.columns, df.dtypes.astype(str)))
    # convert to stata types (ie float64 -> double)
    stata_types = [convert_dtype(col, dt, df) for (col, dt) in raw_dtypes]

    if fname is sys.stdout:
        fname.write('infile dictionary { \n')
        for (stata_type, col) in zip(stata_types, df.columns):
                fname.write(stata_type + ' ' + col + '\n')
        fname.write('}\n')
    else:
        with open(fname, 'w') as f:
            f.write('infile dictionary { \n')
            for (stata_type, col) in zip(stata_types, df.columns):
                    f.write(stata_type + ' ' + col + '\n')
            f.write('}\n')


def convert_dtype(col, dtype, df):
    ''' take a column name, associated pandas datatype, and dataframe.
    Return a reasonable stata type for that column.

    Ints are upcast to long because of the cardinality of location_ids.
    Floats are converted to doubles.
    String lengths are set as the max string in that column

    Returns:
        string to use in stata infile dictionary header
    '''
    if 'int' in dtype:
        return 'long'
    if 'float' in dtype:
        return 'double'
    else:
        return 'str' + str(int(df[col].str.len().max()))
