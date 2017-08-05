#distutils: language=c++
import logging
import sys
cimport graphics

# Emulator constants
cdef int CHIP8_WIDTH_PIXELS = 64
cdef int CHIP8_HEIGHT_PIXELS = 32

# Display constants
cdef int SCREEN_WIDTH = 640
cdef int SCREEN_HEIGHT = 480
cdef SDL_Point PIXEL_SIZE = SDL_Point(SCREEN_WIDTH / CHIP8_WIDTH_PIXELS, SCREEN_HEIGHT / CHIP8_HEIGHT_PIXELS)

# Clear screen colors
cdef int SCREEN_CLEAR_RED   = 0x00
cdef int SCREEN_CLEAR_GREEN = 0x00
cdef int SCREEN_CLEAR_BLUE  = 0x00
cdef int SCREEN_CLEAR_ALPHA = 0x00

# Draw screen colors
cdef int SCREEN_DRAW_RED    = 0xFF
cdef int SCREEN_DRAW_GREEN  = 0xFF
cdef int SCREEN_DRAW_BLUE   = 0xFF
cdef int SCREEN_DRAW_ALPHA  = 0xFF

# Correction constant for scancodes to key sym values
cdef Uint8 SCANCODE_SYM_DIFF = 93

keymap = [
    <Uint8>SDL_SCANCODE_A,
    <Uint8>SDL_SCANCODE_E,
    <Uint8>SDL_SCANCODE_Q,
    <Uint8>SDL_SCANCODE_R,
    <Uint8>SDL_SCANCODE_W,
    <Uint8>SDL_SCANCODE_Z,
    <Uint8>SDL_SCANCODE_S,
    <Uint8>SDL_SCANCODE_X,
    <Uint8>SDL_SCANCODE_D,
    <Uint8>SDL_SCANCODE_C,
    <Uint8>SDL_SCANCODE_V,
    <Uint8>SDL_SCANCODE_F,
    <Uint8>SDL_SCANCODE_T,
    <Uint8>SDL_SCANCODE_G,
    <Uint8>SDL_SCANCODE_H,
    <Uint8>SDL_SCANCODE_B
]

cdef class CHIP_Graphics:
    def __cinit__(self):
        window = NULL
        surface = NULL
        renderer = NULL
        evt = NULL

        if( SDL_Init( SDL_INIT_EVERYTHING ) < 0 ):
            print "SDL failed to initialize with the error %s" % SDL_GetError();
        SDL_CreateWindowAndRenderer(SCREEN_WIDTH, SCREEN_HEIGHT, 0, &self.window, &self.renderer)
    
    def __init__(self):
        self.points = set()
        self.running = True
        print "keymap:"
        for i in keymap:
            print i
        print "end keymap"

    def setClearColor(self):
        SDL_SetRenderDrawColor(self.renderer, SCREEN_CLEAR_RED, SCREEN_CLEAR_GREEN, 
                               SCREEN_CLEAR_BLUE, SCREEN_CLEAR_ALPHA)

    def setDrawColor(self):
        SDL_SetRenderDrawColor(self.renderer, SCREEN_DRAW_RED, SCREEN_DRAW_GREEN, 
                               SCREEN_DRAW_BLUE, SCREEN_DRAW_ALPHA)

    def clearScreen(self):
        self.points.clear()
        self.setClearColor()
        SDL_RenderClear(self.renderer)

    def togglePoint(self, x, y):
        cdef int xDrawStart = x * PIXEL_SIZE.x
        cdef int yDrawStart = y * PIXEL_SIZE.y
        returnVal = False
        cdef SDL_Rect tile = SDL_Rect(xDrawStart, yDrawStart, PIXEL_SIZE.x, PIXEL_SIZE.y)
        pointHash = x * SCREEN_WIDTH + y
        if pointHash in self.points:
            self.points.remove(pointHash)
            self.setClearColor()
            returnVal = True
        else:
            self.points.add(pointHash)
            self.setDrawColor()
        SDL_RenderFillRect(self.renderer, &tile)
        return returnVal

    def isRunning(self):
        return self.running

    def render(self):
        SDL_RenderPresent(self.renderer)
        SDL_UpdateWindowSurface(self.window)
        while SDL_PollEvent(&self.evt):
            if self.evt.type == SDL_QUIT:
                self.shutdown()

    def blockUntilKeyPress(self):
        while self.running:
            SDL_WaitEvent(&self.evt)
            #print "event type", self.evt.type
            if self.evt.type == SDL_QUIT:
                self.running = False
                self.shutdown()
            elif self.evt.type == SDL_KEYDOWN:
                scancode = <Uint8>self.evt.key.keysym.sym - SCANCODE_SYM_DIFF
                print scancode
                #print scancode
                for keyIndex, key in enumerate(keymap):
                    print ord(key), "=?=", scancode
                    if scancode == ord(key):
                        return keyIndex

    def printState(self):
       for point in self.points:
        print "(%d, %d)" % (point / SCREEN_WIDTH, point % SCREEN_WIDTH)

    def shutdown(self):
        print "Shutting down graphics library..."
        SDL_DestroyWindow(self.window)
        SDL_Quit()
        sys.exit(0)