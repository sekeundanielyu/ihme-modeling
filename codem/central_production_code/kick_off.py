import subprocess, os, sys, json
import sqlalchemy as sql
import numpy as np

# grab the arguments passed into the python script
user, model_version_id = [sys.argv[1], sys.argv[2]]

if len(sys.argv) > 3:
    db_name = sys.argv[3]
else:
    db_name = "strConnection"


def get_codem_version(model_version_id):
    '''
    (str) -> str, str

    Given a model version id gets the branch and commit of the code
    '''
    DB = "strConnection".format(db_name)
    engine = sql.create_engine(DB); conn = engine.connect()
    call = "SELECT code_version FROM cod.model_version WHERE model_version_id = {0}"
    result = json.loads(conn.execute(call.format(model_version_id)).fetchone()[0])
    return result["branch"], result["commit"]


def clone_codem():
    """
    Clones the codem repo, using the local host keys on odessa, into the
    current directory.
    :return: None
    """
    repo = "strConnection"
    key = "/var/www/html/codem_rsa"
    call = "ssh-agent bash -c 'ssh-add {key}; git clone {repo}'"
    subprocess.call(call.format(key=key, repo=repo), shell=True)


def git(*args):
    """
    Run a list of git commands on the command line
    """
    return subprocess.call("git " + " ".join(list(args)), shell=True)

# get the branch and the commit of codem to be used in this model run
branch, commit = get_codem_version(model_version_id)

branch_dir = "/ihme/codem/code/%s" % model_version_id
commit_dir = "%s/codem" % branch_dir

# create these directories if they do not exist for this models version of codem to live in
if not os.path.exists(branch_dir):
    os.makedirs(branch_dir)

if not os.path.exists(commit_dir):
    os.chdir(branch_dir)
    clone_codem()
    os.chdir(commit_dir)
    git("checkout", branch)
    git("checkout", commit)

# make sure the permissions are open so that any one can use or edit them
os.chdir(commit_dir + "/prod")
subprocess.call("chmod 777 {branch_dir} -R".format(branch_dir=branch_dir), shell=True)

sh_script = commit_dir+"/prod/codeV2.sh"
py_script = commit_dir+"/prod/codeV2.py"


def get_acause(model_version_id):
    """
    Given a valid model_version_id returns the acause for the given model.
    :param model_version_id: int
        Integer referring to a valid model_version_id
    :return: str
        acause name
    """
    DB = "strConnection".format(db_name)
    engine = sql.create_engine(DB); conn = engine.connect()
    call = '''
    SELECT cause_id FROM cod.model_version
        WHERE model_version_id = {model_version_id}
    '''.format(model_version_id=model_version_id)
    result = conn.execute(call)
    cause_id = np.array(result.fetchall())[0, 0]
    conn.close()
    engine = sql.create_engine(DB); conn = engine.connect()
    call = '''
    SELECT acause from shared.cause WHERE cause_id = {cause_id}
    '''.format(cause_id=cause_id)
    result = conn.execute(call)
    acause = np.array(result.fetchall())[0, 0]
    conn.close()
    return acause

acause = get_acause(model_version_id)

# create a directory for this models results to be saved in and make it open to public use
base_dir = "/ihme/codem/data/{0}/{1}".format(acause, model_version_id)

if not os.path.exists(base_dir):
    os.makedirs(base_dir)

subprocess.call("chmod 777 -R {}".format('/'.join(base_dir.split("/")[:-1])), shell=True)

# submit a job for codem run
sudo = 'sudo -u {user} sh -c '.format(user=user)
qsub = '"source /etc/profile.d/sge.sh;/usr/local/bin/SGE/bin/lx-amd64/qsub '
name = '-N cod_{model_version_id}_global -P proj_codem '.format(model_version_id=model_version_id)
outputs = '-e {base_dir}/ -o {base_dir}/ '.format(base_dir=base_dir)
slots = '-pe multi_slot 66 '
scripts = '{sh_script} {py_script} {model_version_id}"' .format(sh_script=sh_script, py_script=py_script,
                                                                model_version_id=model_version_id)

codem_call = sudo + qsub + name + outputs + slots + scripts

process = subprocess.Popen(codem_call, shell=True, stdout=subprocess.PIPE)
out, err = process.communicate()

# use that models job_id to create a watcher job that sends an email if codem fails
job_id = out.split(" ")[2]
hold = "-hold_jid {job_id} -P proj_codem ".format(job_id=job_id)
email_script = "/home/j/WORK/03_cod/02_models/01_code/04_codem_v2/prod/failed_model_email.sh"
cleanup_script = '{email_script} {user} {model_version_id}"'.format(email_script=email_script,
                                                                    user=user,
                                                                    model_version_id=model_version_id)

cleanup_call = sudo + qsub + hold + cleanup_script

subprocess.Popen(cleanup_call, shell=True)
