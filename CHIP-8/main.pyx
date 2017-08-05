# distutils: language=c++

import logging
import random
import sys
import time

from cpython cimport array
import array

cimport graphics
import graphics

from libcpp.vector cimport vector
from libc.string cimport memcpy, memset

ctypedef unsigned char Uint8

cdef extern from "SDL2/SDL.h":
    void SDL_PumpEvents()
    Uint8* SDL_GetKeyboardState(int *numkeys)

# Pause after every instruction
debug = False

GAME_FILE = "ROMs/tetris.rom"

ctypedef unsigned char  BYTE
ctypedef unsigned short WORD

FPS = 60
SPF = 1./FPS
GAME_START_OFFSET = 0x200
CHAR_SPRITE_OFFSET = 0xE50

#cdef BYTE *gameMemory     = [0] * 0xfff
cdef BYTE gameMemory[0xFFF]
#cdef BYTE *registers      = [0] * 16
cdef BYTE           registers[16]
cdef WORD           addressRegister = 0
cdef WORD           programCounter  = GAME_START_OFFSET
cdef vector[WORD]   stack = []
cdef BYTE           screenData[64][32]
cdef BYTE           keys[16]
cdef int            delayTimer
cdef int            soundTimer
cdef Uint8*         pressedKeys

canvas = graphics.CHIP_Graphics()

cdef void printRegisters():
    global registers, addressRegister, programCounter
    for i in range(8):
        print "%x:%x" % (i, registers[i]),
    print ""
    for i in range(8, 16):
        print "%x:%x" % (i, registers[i]),
    print ""
    print "PC:%x\tI:%x" % (programCounter, addressRegister)

logging.basicConfig(format='%(levelname)s:%(message)s', level=logging.INFO)

cdef void reset():
    global addressRegister, gameMemory, keys, programCounter, registers, stack, delayTimer, soundTimer
    #gameMemory = [0] * 0xfff
    #registers = [0] * 16
    memset(<void *> registers, 0, 16 * sizeof(BYTE))
    memset(<void *> keys, 0, 16 * sizeof(BYTE))
    addressRegister = 0
    programCounter = GAME_START_OFFSET
    stack.clear()
    delayTimer = 0
    soundTimer = 0
    addCharSprites()
    with open(GAME_FILE, "rb") as f:
        memory = f.read()
    for i in xrange(len(memory)):
        gameMemory[GAME_START_OFFSET + i] = <BYTE>ord(memory[i])
    canvas.clearScreen()

cdef void readKeyEvents():
    global keys
    SDL_PumpEvents()
    pressedKeys = <Uint8*>SDL_GetKeyboardState(NULL)
    for index, keycode in enumerate(graphics.keymap):
        if pressedKeys[ord(keycode)]:
            keys[index] = 1
        else:
            keys[index] = 0

cdef void decrementCounters():
    global delayTimer, soundTimer
    delayTimer = max(delayTimer-1, 0)
    soundTimer = max(soundTimer-1, 0)

def addCharSprites():
    global gameMemory
    curOffset = CHAR_SPRITE_OFFSET
    characters = {
        0x0:[0b11110000,
             0b10010000,
             0b10010000,
             0b10010000,
             0b11110000
            ],
        0x1:[0b01000000,
             0b01000000,
             0b01000000,
             0b01000000,
             0b01000000
            ],
        0x2:[0b11110000,
             0b00010000,
             0b11110000,
             0b10000000,
             0b11110000
            ],
        0x3:[0b11110000,
             0b00010000,
             0b11110000,
             0b00010000,
             0b11110000
            ],
        0x4:[0b10100000,
             0b10100000,
             0b11110000,
             0b00100000,
             0b00100000
            ],
        0x5:[0b11110000,
             0b10000000,
             0b11110000,
             0b00010000,
             0b11110000
            ],
        0x6:[0b11110000,
             0b10000000,
             0b11110000,
             0b10010000,
             0b11110000
            ],
        0x7:[0b11110000,
             0b00010000,
             0b00100000,
             0b00100000,
             0b00100000
            ],
        0x8:[0b11110000,
             0b10010000,
             0b11110000,
             0b10010000,
             0b11110000
            ],
        0x9:[0b11110000,
             0b10010000,
             0b11110000,
             0b00010000,
             0b11110000
            ],
        0xA:[0b11110000,
             0b10010000,
             0b11110000,
             0b10010000,
             0b10010000
            ],
        0xB:[0b11110000,
             0b10010000,
             0b11100000,
             0b10010000,
             0b11110000
            ],
        0xC:[0b11110000,
             0b10000000,
             0b10000000,
             0b10000000,
             0b11110000
            ],
        0xD:[0b11100000,
             0b10010000,
             0b10010000,
             0b10010000,
             0b11100000
            ],
        0xE:[0b11110000,
             0b10000000,
             0b11110000,
             0b10000000,
             0b11110000
            ],
        0xF:[0b11110000,
             0b10000000,
             0b11110000,
             0b10000000,
             0b10000000
            ]
    }
    for charNum in characters:
        for byte in characters[charNum]:
            gameMemory[curOffset] = byte
            curOffset += 1

cdef WORD getNextOpcode():
    global gameMemory, programCounter
    cdef WORD opcode = gameMemory[programCounter] << 8 | gameMemory[programCounter+1]
    programCounter += 2
    return opcode

cdef void readNextOpcode():
    global registers
    cdef WORD opcode = getNextOpcode()
    logging.debug("Executing opcode %x" % opcode)
    result = {
        0x0000: OC0,
        0x1000: OC1,
        0x2000: OC2,
        0x3000: OC3,
        0x4000: OC4,
        0x5000: OC5,
        0x6000: OC6,
        0x7000: OC7,
        0x8000: OC8,
        0x9000: OC9,
        0xA000: OCA,
        0xB000: OCB,
        0xC000: OCC,
        0xD000: OCD,
        0xE000: OCE,
        0xF000: OCF
    }.get(opcode & 0xF000, OCNotFound)(opcode)

# Opcode routers
cdef OC0(opcode):
    if opcode & 0x0F0F == 0x0000:
        return OC00E0(opcode)
    elif opcode & 0x0F00 == 0x0000:
        return OC00EE(opcode)
    else:
        return OC0NNN(opcode)

cdef OC1(opcode):
    return OC1NNN(opcode)

cdef OC2(opcode):
    return OC2NNN(opcode)

cdef OC3(opcode):
    return OC3XNN(opcode)

cdef OC4(opcode):
    return OC4XNN(opcode)

cdef OC5(opcode):
    return OC5XY0(opcode)

cdef OC6(opcode):
    return OC6XNN(opcode)

cdef OC7(opcode):
    return OC7XNN(opcode)

cdef OC8(opcode):
    return {
        0x0000: OC8XY0,
        0x0001: OC8XY1,
        0x0002: OC8XY2,
        0x0003: OC8XY3,
        0x0004: OC8XY4,
        0x0005: OC8XY5,
        0x0006: OC8XY6,
        0x0007: OC8XY7,
        0x000E: OC8XYE
    }.get(opcode & 0x000F, OCNotFound)(opcode)

cdef OC9(opcode):
    return OC9XY0(opcode)

cdef OCA(opcode):
    return OCANNN(opcode)

cdef OCB(opcode):
    return OCBNNN(opcode)

cdef OCC(opcode):
    return OCCXNN(opcode)

cdef OCD(opcode):
    return OCDXYN(opcode)

cdef OCE(opcode):
    if opcode & 0x000F == 0x000E:
        return OCEX9E(opcode)
    else:
        return OCEXA1(opcode)

cdef OCF(opcode):

    return {
        0x0007: OCFX07,
        0x000A: OCFX0A,
        0x0015: OCFX15,
        0x0018: OCFX18,
        0x001E: OCFX1E,
        0x0029: OCFX29,
        0x0033: OCFX33,
        0x0055: OCFX55,
        0x0065: OCFX65
    }.get(opcode & 0x00FF, OCNotFound)(opcode)

# Opcode definitions
cdef OC0NNN(opcode):
    """
    0NNN: Calls RCA1802 at address NNN. IDK what this is but it shouldn't be necessary for most cases.
    """
    logging.error("Opcode 0NNN not implemented")

cdef OC00E0(opcode):
    """
    00E0: Clears the screen
    """
    global canvas
    canvas.clearScreen()

cdef OC00EE(opcode):
    """
    00EE: Return
    """
    global stack, programCounter
    cdef WORD jump_to = stack.back()
    stack.pop_back()
    programCounter = jump_to

cdef OC1NNN(opcode):
    """
    1NNN: Jump to address NNN
    """
    global programCounter
    programCounter = opcode & 0x0FFF

cdef OC2NNN(opcode):
    """
    2NNN: Call subroutine NNN
    """
    global stack, programCounter
    stack.push_back(programCounter & 0xFFF)
    programCounter = opcode & 0x0FFF

cdef OC3XNN(opcode):
    """
    3XNN: Skip next instruction if RegX == NN
    """
    global registers, programCounter
    regNum = (opcode & 0x0F00) >> 8
    value = opcode & 0x00FF
    if registers[regNum] == value:
        programCounter += 2


cdef OC4XNN(opcode):
    """
    4XNN: Skip next instruction if RegX != NN
    """
    global registers, programCounter
    regNum = (opcode & 0x0F00) >> 8
    value = opcode & 0x00FF
    if not registers[regNum] == value:
        programCounter += 2

cdef OC5XY0(opcode):
    """
    5XY0: Skip next instruction if RegX == RegY
    """
    global registers, programCounter
    reg1 = (opcode & 0x0F00) >> 8
    reg2 = (opcode & 0x00F0) >> 4
    if registers[reg1] == registers[reg2]:
        programCounter += 2

cdef OC6XNN(opcode):
    """
    6XNN: Sets RegX = NN
    """
    global registers
    regNum = (opcode & 0x0F00) >> 8
    registers[regNum] = opcode & 0x00FF

cdef OC7XNN(opcode):
    """
    7XNN: Set RegX = RegX + NN
    """
    global registers
    regNum = (opcode & 0x0F00) >> 8
    registers[regNum] = <Uint8>((registers[regNum] + (opcode & 0x00FF)) % 256)

cdef OC8XY0(opcode):
    """
    8XY0: RegX = RegY
    """
    global registers
    x = (opcode & 0x0F00) >> 8
    y = (opcode & 0x00F0) >> 4
    registers[x] = registers[y]

cdef OC8XY1(opcode):
    """
    8XY1: RegX = RegX | RegY (bitwise OR)
    """
    global registers
    x = (opcode & 0x0F00) >> 8
    y = (opcode & 0x00F0) >> 4
    registers[x] |= registers[y]

cdef OC8XY2(opcode):
    """
    8XY2: RegX = RegX & RegY (bitwise AND)
    """
    global registers
    x = (opcode & 0x0F00) >> 8
    y = (opcode & 0x00F0) >> 4
    registers[x] &= registers[y]

cdef OC8XY3(opcode):
    """
    8XY3: RegX = RegX ^ RegY (bitwise XOR)
    """
    global registers
    x = (opcode & 0x0F00) >> 8
    y = (opcode & 0x00F0) >> 4
    registers[x] ^= registers[y]

cdef OC8XY4(opcode):
    """
    8XY4: RegX = RegX + RegY, RegF = carry
    """
    global registers
    x = (opcode & 0x0F00) >> 8
    y = (opcode & 0x00F0) >> 4
    registers[x] += registers[y]
    if registers[x] < registers[y]:
        registers[0xF] = 1
    else:
        registers[0xF] = 0

cdef OC8XY5(opcode):
    """
    8XY5: RegX = RegX - RegY, RegF = borrow
    """
    global registers
    x = (opcode & 0x0F00) >> 8
    y = (opcode & 0x00F0) >> 4
    if registers[x] > registers[y]:
        registers[0xF] = 0
    else:
        registers[0xF] = 1
    registers[x] -= registers[y]

cdef OC8XY6(opcode):
    """
    8XY6: RegF = LSB(RegX), RegX = RegX >> 1
    """
    global registers
    x = (opcode & 0x0F00) >> 8
    registers[0xF] = registers[x] & 1
    registers[x] >>= 1

cdef OC8XY7(opcode):
    """
    8XY7: RegX = RegY - RegX
    """
    global registers
    x = (opcode & 0x0F00) >> 8
    y = (opcode & 0x00F0) >> 4
    if registers[x] < registers[y]:
        registers[0xF] = 0
    else:
        registers[0xF] = 1
    registers[x] = registers[y] - registers[x]

cdef OC8XYE(opcode):
    """
    8XYE: RegF = MSB(RegX), RegX  = RegX << 1
    """
    global registers
    x = (opcode & 0x0F00) >> 8
    registers[0xF] = (registers[x] & 0xF) >> 3
    registers[x] <<= 1

cdef OC9XY0(opcode):
    """
    9XY0: Skip next instruction if RegX != RegY
    """
    global registers, programCounter
    x = (opcode & 0x0F00) >> 8
    y = (opcode & 0x00F0) >> 4
    if not registers[x] == registers[y]:
        programCounter += 2

cdef OCANNN(opcode):
    """
    ANNN: Sets addressRegister to address NNN
    """
    global addressRegister
    addressRegister = opcode & 0x0FFF

cdef OCBNNN(opcode):
    """
    BNNN: Set PC to Reg0 + NNN
    """
    global registers, programCounter
    programCounter = registers[0] + (opcode & 0x0FFF)

cdef OCCXNN(opcode):
    """
    CXNN: RegX = rand(0-255) & NN
    """
    global registers
    regNum = (opcode & 0x0F00) >> 8
    registers[regNum] = random.randint(0, 255) & (opcode & 0x00FF)

cdef OCDXYN(opcode):
    """
    DXYN: Draw sprite at coordinate (RegX, RegY) of width 8
          Sprite has height of N
          Each row is consecutive values starting at addressRegister
    """
    global addressRegister, canvas, gameMemory, registers
    registers[0xF] = 0
    x = (opcode & 0x0F00) >> 8
    y = (opcode & 0x00F0) >> 4
    n = (opcode & 0x000F)
    regX = registers[x]
    regY = registers[y]
    for row in xrange(n):
        byteRow = gameMemory[addressRegister + row]
        for iterIdx, bitIdx in enumerate(xrange(7, -1, -1)):
            bit = (byteRow >> bitIdx) & 0x1
            if bit == 1:
                logging.debug("Toggling point at (%d, %d)" % (regX + iterIdx, regY + row))
                isBitUnset = canvas.togglePoint(regX + iterIdx, regY + row)
                if isBitUnset:
                    registers[0xF] = 1

cdef OCEX9E(opcode):
    """
    EX9E: Skip next instruction if key stored in RegX is pressed
    """
    global keys, programCounter, registers
    x = (opcode & 0x0F00) >> 8
    if keys[registers[x]] == 1:
        programCounter += 2

cdef OCEXA1(opcode):
    """
    EXA1: Skip next instruction if key stored in RegX is NOT pressed
    """
    global keys, programCounter, registers
    x = (opcode & 0x0F00) >> 8
    if keys[registers[x]] == 0:
        programCounter += 2

cdef OCFX07(opcode):
    """
    FX07: Set RegX = delayTimer
    """
    global registers, delayTimer
    x = (opcode & 0x0F00) >> 8
    registers[x] = delayTimer

cdef OCFX0A(opcode):
    """
    FX0A: Keypress awaited, then stored in RegX. Blocking operation
    """
    global registers
    print "getting keypress"
    keypress = canvas.blockUntilKeyPress()
    print "keypress is", int(keypress)
    x = (opcode & 0x0F00) >> 8
    registers[x] = keypress

cdef OCFX15(opcode):
    """
    FX15: Sets delayTimer to RegX
    """
    global delayTimer, registers
    x = (opcode & 0x0F00) >> 8
    delayTimer = registers[x]

cdef OCFX18(opcode):
    """
    FX18: Sets soundTimer to RegX
    """
    global soundTimer, registers
    x = (opcode & 0x0F00) >> 8
    soundTimer = registers[x]

cdef OCFX1E(opcode):
    """
    FX1E: Adds RegX to I
    """
    global addressRegister, registers
    x = (opcode & 0x0F00) >> 8
    addressRegister += registers[x]

cdef OCFX29(opcode):
    """
    FX29: Sets I to the location of sprite for character in RegX
    """
    global addressRegister, registers
    x = (opcode & 0x0F00) >> 8
    spriteLoc = registers[x]
    if spriteLoc > 0xF:
        logging.warning("FX29 tried to access sprite larger than 0xF")
    addressRegister = CHAR_SPRITE_OFFSET + 5 * spriteLoc

cdef OCFX33(opcode):
    """
    FX33: Store the BCD of RegX at I
    """
    global addressRegister, gameMemory, registers
    x = (opcode & 0x0F00) >> 8
    regX = registers[x]
    gameMemory[addressRegister + 2] = regX % 10
    regX /= 10
    gameMemory[addressRegister + 1] = regX % 10
    regX /= 10
    gameMemory[addressRegister] = regX % 10

cdef OCFX55(opcode):
    """
    FX55: Stores Reg0 to RegX at I
    """
    global addressRegister, gameMemory, registers
    x = (opcode & 0x0F00) >> 8
    for reg in range(x+1):
        gameMemory[addressRegister + reg] = registers[reg]

cdef OCFX65(opcode):
    """
    FX65: Loads Reg0 to RegX from I
    """
    global addressRegister, gameMemory, registers
    x = (opcode & 0x0F00) >> 8
    for reg in range(x+1):
        registers[reg] = gameMemory[addressRegister + reg]

cdef OCNotFound(opcode):
    logging.error("Could not read opcode %x" % opcode)

reset()
while True:
    t = time.time()
    readKeyEvents()
    readNextOpcode()
    if not canvas.isRunning():
        sys.exit()
    canvas.render()
    decrementCounters()
    if debug:
        printRegisters()
        canvas.printState()
        k = raw_input()
        if k=="q":
            canvas.shutdown()
    else:
        timeDiff = time.time() - t
        if timeDiff < SPF:
            time.sleep(timeDiff)
