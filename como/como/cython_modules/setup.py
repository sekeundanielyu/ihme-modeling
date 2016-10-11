from distutils.core import setup
from Cython.Distutils import Extension
from Cython.Distutils import build_ext
import numpy as np
import cython_gsl

setup(
    include_dirs=['strDir/include'],
    cmdclass={'build_ext': build_ext},
    ext_modules=[
        Extension(
            "*",
            ["*.pyx"],
            libraries=cython_gsl.get_libraries(),
            library_dirs=[cython_gsl.get_library_dir()],
            include_dirs=[np.get_include(), 'strDir/include'])]
    )
