import warnings
from jobmon import qmaster


class ResubFailedQ(qmaster.MonitoredQ):

    def __init__(self, resubmits=0, *args, **kwargs):
        super(ResubFailedQ, self).__init__(*args, **kwargs)
        self.resubmits = resubmits

    def manage_exit_q(self, exit_jobs):
        """custom exit queue management. Jobs that have logged a failed state
        automagically resubmit themselves 'retries' times. default is 0.

        Args:
            exit_jobs (int): sge job id of any jobs that have left the queue
                between concurrent qmanage() calls
        """

        query_status = """
        SELECT
            current_status, jid
        FROM
            job
        JOIN
            sgejob USING (jid)
        WHERE
        """
        query_failed = """
        SELECT
            COUNT(*) as num,
            jid
        FROM
            job
        JOIN
            sgejob USING (jid)
        JOIN
            job_status USING (jid)
        WHERE
            status = 3"""

        for sgeid in exit_jobs:
            result = self.manager.query(
                query_status + "sgeid = {sgeid};".format(sgeid=sgeid))[1]
            try:
                current_status = result["current_status"].item()
                jid = result["jid"].item()
            except ValueError:
                current_status = None

            if current_status is None:
                warnings.warn(("sge job {id} left the sge queue without "
                               "registering in 'sgejob' table"
                               ).format(id=sgeid))
            if current_status == 1:
                warnings.warn(("sge job {id} left the sge queue without "
                               "ever changing status to submitted. This is "
                               "highly unlikely.").format(id=sgeid))
            elif current_status == 2:
                warnings.warn(("sge job {id} left the sge queue without "
                               "starting job execution. this is probably "
                               "bad.").format(id=sgeid))
            elif current_status == 3:
                warnings.warn(("sge job {id} left the sge queue after "
                               "starting job execution. but did not "
                               "register an error and did not register "
                               "completed. This is probably bad."
                               ).format(id=sgeid))
            elif current_status == 4:
                fails = self.manager.query(
                    query_failed + " AND sgeid = {id};".format(id=sgeid))[1]
                if fails["num"].item() < self.resubmits + 1:
                    jid = fails["jid"].item()
                    print "retrying " + str(jid)
                    self.qsub(runfile=self.jobs[jid]["runfile"],
                              jobname=self.jobs[jid]["jobname"],
                              jid=jid,
                              parameters=self.jobs[jid]["parameters"],
                              *self.jobs[jid]["args"],
                              **self.jobs[jid]["kwargs"])
            elif current_status == 5:
                del(self.jobs[jid])
            else:
                warnings.warn(("sge job {id} left the sge queue after "
                               "after registering an unknown status "
                               ).format(id=sgeid))
