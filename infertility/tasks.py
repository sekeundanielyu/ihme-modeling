import luigi
import os
import shutil
import json
import time
import pandas as pd
from jobmon import qmaster
from task_master import builder
from task_master.process_node import process, anchor
os.chdir(os.path.dirname(os.path.realpath(__file__)))
from job_utils import getset

root = os.path.join(os.path.dirname(os.path.realpath(__file__)), "..")

# make log directory
if not os.path.exists(os.path.join(root, "logs")):
    os.makedirs(os.path.join(root, "logs"))
else:
    shutil.rmtree(os.path.join(root, "logs"))
    os.makedirs(os.path.join(root, "logs"))

# descriptions
env_description = "Third env run"
pid_split_description = "Third pid split"
female_attr_description = "Third female attribution"
male_attr_description = "Third male attribution"
excess_description = "Second excess redistribution"


class _BaseBuild(builder.TaskBuilder):

    task_builder = luigi.Parameter(
        significant=False,
        default=("task_master.process_node.builders.JSONProcessAnchorMap?"
                 "{root}/infertility/maps/full.json".format(root=root)))

    @luigi.Task.event_handler(luigi.Event.FAILURE)
    def mourn_failure(task, exception):
        df = pd.DataFrame({"process": task.identity,
                           "error": str(exception)},
                          index=[0])
        df.to_csv("{root}/logs/{process}.csv".format(root=root,
                                                     process=task.identity))


class ModelableEntity(_BaseBuild, anchor.ModelableEntity):
    pass


class Envelope(_BaseBuild, process.PyProcess):

    def execute(self):

        # compile submission arguments
        kwargs = self.build_args[1]
        male_prop_id = kwargs.pop("male_prop_id")
        female_prop_id = kwargs.pop("female_prop_id")
        exp_id = kwargs.pop("exp_id")
        env_id = kwargs.pop("env_id")
        male_env_id = kwargs.pop("male_env_id")
        female_env_id = kwargs.pop("female_env_id")

        # make server directory
        directory = "{root}/{proc}".format(root=root, proc=self.identity)
        if not os.path.exists(directory):
            os.makedirs(directory)
        else:
            shutil.rmtree(directory)
            os.makedirs(directory)

        # make output directories
        for _id in [male_env_id, female_env_id]:
            sub_dir = os.path.join(directory, str(_id))
            if not os.path.exists(sub_dir):
                os.makedirs(sub_dir)
            else:
                shutil.rmtree(sub_dir)
                os.makedirs(sub_dir)

        env_params = ["--male_prop_id", male_prop_id, "--female_prop_id",
                      female_prop_id, "--exp_id", exp_id, "--env_id", env_id,
                      "--male_env_id", male_env_id, "--female_env_id",
                      female_env_id, "--out_dir", directory, "--year_id"]

        q = qmaster.MonitoredQ(directory, request_timeout=30000)  # monitor
        try:

            # parallelize by location
            for i in [i for i in range(1990, 2016, 5)]:
                q.qsub(
                    runfile="{root}/infertility/calc_env.py".format(root=root),
                    jobname="{proc}_{loc}".format(proc=self.identity,
                                                  loc=i),
                    parameters=env_params + [i],
                    slots=7,
                    memory=14,
                    project="proj_custom_models")
            q.qblock(poll_interval=60)  # monitor them
            fail = q.manager.query(
                "select count(*) as num from job where current_status != 5;"
            )[1]["num"].item()
            if fail > 0:
                raise Exception("Not all jobs finished")

            # save the results
            for save_id in [male_env_id, female_env_id]:

                save_params = [
                    save_id, env_description,
                    os.path.join(directory, str(save_id)), "--best",
                    "--file_pattern", "{year_id}.h5", "--h5_tablename", "data"]
                q.qsub(
                    runfile=(
                        "/home/j/WORK/10_gbd/00_library/adding_machine"
                        "/bin/save_custom_results"),
                    jobname="save_" + str(save_id),
                    parameters=save_params,
                    slots=20,
                    memory=40,
                    project="proj_custom_models")
            q.qblock(poll_interval=60)  # monitor them
            fail = q.manager.query(
                "select count(*) as num from job where current_status != 5;"
            )[1]["num"].item()
            if fail > 0:
                raise Exception("Not all jobs finished")
        finally:
            q.stop_monitor()  # stop monitor


class PID(_BaseBuild, process.PyProcess):

    def execute(self):

        # compile submission arguments
        kwargs = self.build_args[1]
        pid_env_id = kwargs.pop("pid_env_id")
        chlam_prop_id = kwargs.pop("chlam_prop_id")
        gono_prop_id = kwargs.pop("gono_prop_id")
        other_prop_id = kwargs.pop("other_prop_id")
        chlam_id = kwargs.pop("chlam_id")
        gono_id = kwargs.pop("gono_id")
        other_id = kwargs.pop("other_id")

        # make server directory
        directory = "{root}/{proc}".format(root=root, proc=self.identity)
        if not os.path.exists(directory):
            os.makedirs(directory)
        else:
            shutil.rmtree(directory)
            os.makedirs(directory)

        split_params = [
            pid_env_id,
            "--target_meids", chlam_id, gono_id, other_id,
            "--prop_meids", chlam_prop_id, gono_prop_id, other_prop_id,
            "--split_meas_ids", 5, 6,
            "--prop_meas_id", 18,
            "--output_dir", directory]

        q = qmaster.MonitoredQ(directory, request_timeout=30000)  # monitor
        try:
            q.qsub(
                runfile=("/home/j/WORK/10_gbd/00_library/transmogrifier"
                         "/transmogrifier/epi.py"),
                jobname=self.identity,
                parameters=split_params,
                slots=40,
                memory=60,
                project="proj_custom_models")
            q.qblock(poll_interval=60)  # monitor them
            fail = q.manager.query(
                "select count(*) as num from job where current_status != 5;"
            )[1]["num"].item()
            if fail > 0:
                raise Exception("Not all jobs finished")

            # save the results
            for save_id in [chlam_id, gono_id, other_id]:

                save_params = [
                    save_id, pid_split_description,
                    os.path.join(directory, str(save_id)), "--best",
                    "--sexes", "2", "--file_pattern", "{location_id}.h5",
                    "--h5_tablename", "draws"]
                q.qsub(
                    runfile=(
                        "/home/j/WORK/10_gbd/00_library/adding_machine"
                        "/bin/save_custom_results"),
                    jobname="save_" + str(save_id),
                    parameters=save_params,
                    slots=20,
                    memory=40,
                    project="proj_custom_models")
            q.qblock(poll_interval=60)  # monitor them
            fail = q.manager.query(
                "select count(*) as num from job where current_status != 5;"
            )[1]["num"].item()
            if fail > 0:
                raise Exception("Not all jobs finished")
        finally:
            q.stop_monitor()  # stop monitor


class Westrom(_BaseBuild, process.PyProcess):

    def execute(self):

        # compile submission arguments
        kwargs = self.build_args[1]
        source_me_id = kwargs.pop("source_me_id")
        target_me_id = kwargs.pop("target_me_id")

        # make server directory
        directory = "{root}/{proc}".format(root=root, proc=self.identity)
        if not os.path.exists(directory):
            os.makedirs(directory)
        else:
            shutil.rmtree(directory)
            os.makedirs(directory)

        west_params = [
            "--source_me_id", source_me_id,
            "--target_me_id", target_me_id
        ]

        q = qmaster.MonitoredQ(directory, request_timeout=30000)  # monitor
        try:
            q.qsub(
                runfile="{root}/infertility/westrom.py".format(root=root),
                jobname=self.identity,
                parameters=west_params,
                slots=10,
                memory=20,
                project="proj_custom_models")
            q.qblock(poll_interval=60)  # monitor them
            fail = q.manager.query(
                "select count(*) as num from job where current_status != 5;"
            )[1]["num"].item()
            if fail > 0:
                raise Exception("Not all jobs finished")
        finally:
            q.stop_monitor()  # stop monitor


class FemaleInfert(_BaseBuild, process.PyProcess):

    def execute(self):

        # compile submission arguments
        me_map = self.build_args[0][0]

        # make server directory
        directory = "{root}/{proc}".format(root=root, proc=self.identity)
        if not os.path.exists(directory):
            os.makedirs(directory)
        else:
            shutil.rmtree(directory)
            os.makedirs(directory)

        # make output directories
        save_ids = []
        for mapper in me_map.values():
            outputs = mapper.get("trgs", {})
            for me_id in outputs.values():
                os.makedirs(os.path.join(directory, str(me_id)))
                save_ids.append(me_id)

        attr_params = ["--me_map", json.dumps(me_map),
                       "--out_dir", directory,
                       "--location_id"]

        q = qmaster.MonitoredQ(directory, request_timeout=120000)  # monitor
        try:

            # attribution jobs by location_id
            for i in getset.get_most_detailed_location_ids():
                q.qsub(
                    runfile="{root}/infertility/female_attr.py".format(
                        root=root),
                    jobname="{proc}_{loc}".format(proc=self.identity,
                                                  loc=i),
                    parameters=attr_params + [i],
                    slots=4,
                    memory=8,
                    project="proj_custom_models")
                time.sleep(1.5)
            q.qblock(poll_interval=60)  # monitor them
            fail = q.manager.query(
                "select count(*) as num from job where current_status != 5;"
            )[1]["num"].item()
            if fail > 0:
                raise Exception("Not all attr jobs finished")

            # save the results
            for save_id in save_ids:

                save_params = [
                    save_id, female_attr_description,
                    os.path.join(directory, str(save_id)), "--best",
                    "--sexes", "2", "--file_pattern", "{location_id}.h5",
                    "--h5_tablename", "data"]
                q.qsub(
                    runfile=(
                        "/home/j/WORK/10_gbd/00_library/adding_machine"
                        "/bin/save_custom_results"),
                    jobname="save_" + str(save_id),
                    parameters=save_params,
                    slots=20,
                    memory=40,
                    project="proj_custom_models")
            q.qblock(poll_interval=60)  # monitor them
            fail = q.manager.query(
                "select count(*) as num from job where current_status != 5;"
            )[1]["num"].item()
            if fail > 0:
                raise Exception("Not all save jobs finished")
        finally:
            q.stop_monitor()  # stop monitor


class MaleInfert(_BaseBuild, process.PyProcess):

    def execute(self):

        # compile submission arguments
        me_map = self.build_args[0][0]

        # make server directory
        directory = "{root}/{proc}".format(root=root, proc=self.identity)
        if not os.path.exists(directory):
            os.makedirs(directory)
        else:
            shutil.rmtree(directory)
            os.makedirs(directory)

        # make output directories
        save_ids = []
        for mapper in me_map.values():
            outputs = mapper.get("trgs", {})
            for me_id in outputs.values():
                os.makedirs(os.path.join(directory, str(me_id)))
                save_ids.append(me_id)

        attr_params = ["--me_map", json.dumps(me_map),
                       "--out_dir", directory,
                       "--year_id"]

        q = qmaster.MonitoredQ(directory, request_timeout=30000)  # monitor
        try:

            # attribution jobs by year_id
            for i in [i for i in range(1990, 2016, 5)]:
                q.qsub(
                    runfile="{root}/infertility/male_attr.py".format(
                        root=root),
                    jobname="{proc}_{year}".format(proc=self.identity,
                                                   year=i),
                    parameters=attr_params + [i],
                    slots=3,
                    memory=6,
                    project="proj_custom_models")
            q.qblock(poll_interval=60)  # monitor them
            fail = q.manager.query(
                "select count(*) as num from job where current_status != 5;"
            )[1]["num"].item()
            if fail > 0:
                raise Exception("Not all attr jobs finished")

            # save the results
            for save_id in save_ids:

                save_params = [
                    save_id, male_attr_description,
                    os.path.join(directory, str(save_id)), "--best",
                    "--sexes", "1", "--file_pattern", "{year_id}.h5",
                    "--h5_tablename", "data"]
                q.qsub(
                    runfile=(
                        "/home/j/WORK/10_gbd/00_library/adding_machine"
                        "/bin/save_custom_results"),
                    jobname="save_" + str(save_id),
                    parameters=save_params,
                    slots=20,
                    memory=40,
                    project="proj_custom_models")
            q.qblock(poll_interval=60)  # monitor them
            fail = q.manager.query(
                "select count(*) as num from job where current_status != 5;"
            )[1]["num"].item()
            if fail > 0:
                raise Exception("Not all save jobs finished")
        finally:
            q.stop_monitor()  # stop monitor


class Excess(_BaseBuild, process.PyProcess):

    def execute(self):

        kwargs = self.build_args[1]
        excess_id = kwargs.pop("excess")
        redist_map = kwargs.pop("redist")

        # make server directory
        directory = "{root}/{proc}".format(root=root, proc=self.identity)
        if not os.path.exists(directory):
            os.makedirs(directory)
        else:
            shutil.rmtree(directory)
            os.makedirs(directory)

        # make output directories
        for me_id in redist_map.values():
            sub_dir = os.path.join(directory, str(me_id))
            if not os.path.exists(sub_dir):
                os.makedirs(sub_dir)
            else:
                shutil.rmtree(sub_dir)
                os.makedirs(sub_dir)

        exs_params = ["--excess_id", excess_id,
                      "--redist_map", json.dumps(redist_map),
                      "--out_dir", directory,
                      "--year_id"]

        q = qmaster.MonitoredQ(directory, request_timeout=120000)  # monitor
        try:

            # attribution jobs by location_id
            for i in [i for i in range(1990, 2016, 5)]:
                q.qsub(
                    runfile="{root}/infertility/excess.py".format(
                        root=root),
                    jobname="{proc}_{loc}".format(proc=self.identity,
                                                  loc=i),
                    parameters=exs_params + [i],
                    slots=5,
                    memory=10,
                    project="proj_custom_models")
                time.sleep(1.5)
            q.qblock(poll_interval=60)  # monitor them
            fail = q.manager.query(
                "select count(*) as num from job where current_status != 5;"
            )[1]["num"].item()
            if fail > 0:
                raise Exception("Not all attr jobs finished")

            # save the results
            for save_id in redist_map.values():

                save_params = [
                    save_id, excess_description,
                    os.path.join(directory, str(save_id)), "--best",
                    "--sexes", "2", "--file_pattern", "{year_id}.h5",
                    "--h5_tablename", "data"]
                q.qsub(
                    runfile=(
                        "/home/j/WORK/10_gbd/00_library/adding_machine"
                        "/bin/save_custom_results"),
                    jobname="save_" + str(save_id),
                    parameters=save_params,
                    slots=20,
                    memory=40,
                    project="proj_custom_models")
            q.qblock(poll_interval=60)  # monitor them
            fail = q.manager.query(
                "select count(*) as num from job where current_status != 5;"
            )[1]["num"].item()
            if fail > 0:
                raise Exception("Not all save jobs finished")
        finally:
            q.stop_monitor()  # stop monitor


class Hook(_BaseBuild, process.ShellProcess):
    pass


if __name__ == "__main__":
    luigi.run()
