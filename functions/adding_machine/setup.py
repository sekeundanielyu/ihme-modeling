from setuptools import setup
from setuptools.command.install import install
from subprocess import check_output
import json


class _install(install):
    def run(self):
        cmd = ['git', '--work-tree=%s', 'rev-parse', '--abbrev-ref', 'HEAD']
        branch = check_output(cmd).strip()
        cmd = ['git', '--work-tree=%s', 'rev-parse', 'HEAD']
        commit = check_output(cmd).strip()
        with open("adding_machine/__version__.txt", "w") as vfile:
            json.dump({
                'path': 'repoURL',
                'branch': branch,
                'commit': commit}, vfile)
        install.run(self)


setup(
    cmdclass={'install': _install},
    name='adding_machine',
    version_command=('git describe --always', "pep440-git-dev"),
    description="Draw-level aggregation and summarization",
    install_requires=[
        'pandas',
        'sqlalchemy',
        'numpy',
        'pymysql'],
    package_data={
        'adding_machine': ['*.default', '__version__.txt']},
    include_package_data=True,
    packages=['adding_machine'],
    scripts=[
        'bin/aggregate_mvid',
        'bin/save_custom_results',
        'bin/launch_splits',
        'bin/split_me',
        'bin/get_pct_change.py'])
