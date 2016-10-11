from setuptools import setup, find_packages
from setuptools.command.install import install
from subprocess import check_output
from setuptools.extension import Extension
from Cython.Build import cythonize
import numpy as np
import cython_gsl
import json

url = "https://stash.ihme.washington.edu/projects/CC/repos/como"


class _install(install):
    def run(self):
        cmd = ['git', '--work-tree=%s', 'rev-parse', '--abbrev-ref', 'HEAD']
        branch = check_output(cmd).strip()
        cmd = ['git', '--work-tree=%s', 'rev-parse', 'HEAD']
        commit = check_output(cmd).strip()
        with open("como/__version__.txt", "w") as vfile:
            json.dump({
                'path': url,
                'branch': branch,
                'commit': commit}, vfile)
        install.run(self)


extensions = [Extension(
    "como/cython_modules/*",
    ["como/cython_modules/*.pyx"],
    libraries=cython_gsl.get_libraries(),
    library_dirs=[cython_gsl.get_library_dir()],
    include_dirs=[
        np.get_include(),
        'strDir/include'])]

setup(
    cmdclass={'install': _install},
    name='como',
    version_command=('git describe --always', "pep440-git-dev"),
    description="Comorbidity simulator",
    url=url,
    install_requires=[
        'pandas',
        'sqlalchemy',
        'numpy',
        'pymysql'],
    package_data={
        'como': ['config/*', 'dws/combine/*', '__version__.txt'],
        'como.cython_modules': ['*.*']},
    include_package_data=True,
    packages=find_packages(),
    scripts=[
        'bin/run_como',
        'bin/simulate_cys',
        'bin/agg_year_sex',
        'bin/run_agg',
        'bin/run_summ',
        'bin/run_impairments',
        'bin/calc_impairments',
        'bin/summ_loc',
        'bin/upload',
        'bin/gini_leaf',
        'bin/gini_agg',
        'bin/run_gini'],
    ext_modules=cythonize(extensions))
