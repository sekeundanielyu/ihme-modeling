import sys
import os
import upload
import fit_stats
import drill
import subprocess
from jobmon import sge, job
from adding_machine.agg_locations import aggregate_mvid

# Set default file mask to readable-for all users
os.umask(0o0002)

if __name__ == "__main__":

    mvid = sys.argv[1]
    j = job.Job('%s/%s' % (drill.settings['cascade_ode_out_dir'], mvid))
    j.start()

    try:
        commit_hash = sge.get_commit_hash(dir='%s/..' % drill.this_path)
        upload.set_commit_hash(mvid, commit_hash)
        upload.upload_model(mvid)

        outdir = "%s/%s/full" % (
            drill.settings['cascade_ode_out_dir'],
            str(mvid))
        joutdir = "%s/%s" % (drill.settings['diag_out_dir'], mvid)
        logdir = '%s/%s' % (drill.settings['log_dir'], mvid)
        fit_stats.write_fit_stats(mvid, outdir, joutdir)
        upload.upload_fit_stat(mvid)

        # Write effect PDFs
        plotter = "%s/../diagnostics/effect_plots.r" % drill.this_path
        plotter = os.path.realpath(plotter)

        try:
            subprocess.check_output([
                "/usr/local/R-current/bin/Rscript",
                plotter,
                str(mvid),
                joutdir,
                drill.settings['cascade_ode_out_dir']],
                stderr=subprocess.STDOUT)
        except subprocess.CalledProcessError as e:
            raise Exception('Error in effect plots: %s' % e.output)

        # Launch final aggregations
        odbcfile = os.path.realpath("%s/../.odbc.ini" % drill.this_path)
        aggregate_mvid(
                mvid,
                env='cascade-prod',
                custom_file_pattern='{location_id}_{year_id}_{sex_id}.h5',
                h5_tablename='draws',
                single_file=False,
                odbc_filepath=odbcfile)
        j.finish()
        j.send_request('stop')

    except Exception as e:
        print(str(e))
        j.log_error(str(e))
        j.failed()
