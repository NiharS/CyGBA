from distutils.core import setup
from distutils.extension import Extension
from Cython.Build import cythonize

ext_modules = [
		# Extension("graphics", ["graphics.pyx"], language='c++'),
		# Extension("main", ["main.pyx"], language='c++')
		Extension("*", sources=["*.pyx"], libraries=["SDL2"], language="c++")
	]

setup(
  name = 'MyProject',
  ext_modules = cythonize(ext_modules),
)