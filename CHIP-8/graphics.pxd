#distutils: language=c++

from cSDL cimport *
from libcpp cimport bool

cdef Uint8* keymap

cdef class CHIP_Graphics:
	cdef SDL_Window *window
	cdef SDL_Surface *surface
	cdef SDL_Renderer *renderer
	cdef SDL_Event evt
	cdef set points
	cdef bool running