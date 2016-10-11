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
        with open("transmogrifier/__version__.txt", "w") as vfile:
            json.dump({
                'path': 'strURL',
                'branch': branch,
                'commit': commit}, vfile)
        install.run(self)

setup(
    cmdclass={'install': _install},
    name='transmogrifier',
    version_command=('git describe --always', "pep440-git-dev"),
    description="""
        Utilities for common draw-level operations, such as splitting and
        scaling""",
    url='strURL',
    install_requires=[
        'pandas',
        'sqlalchemy',
        'numpy',
        'pymysql',
        'pytables',
        'parse'],
    package_data={
        'transmogrifier': ['*.default', '__version__.txt'],
        'transmogrifier.risk_utils.db_tools.core': ['*.default']},
    packages=[
        'transmogrifier',
        'transmogrifier.risk_utils',
        'transmogrifier.risk_utils.db_tools',
        'transmogrifier.risk_utils.db_tools.api',
        'transmogrifier.risk_utils.db_tools.core'])
