import core.sys.windows.windows;

import std.conv;
import std.file;
import std.stdio;
import std.string;

int main() {
	ubyte fps;
	try {
		writeln("Enter fps to generate patch for: ");
		fps = readln.strip.to!ubyte;
	} catch (Exception e) {
		writeln("Not a number from 0-255");
		return 1;
	}

	HMODULE h = LoadLibraryExA("Engine.dll".toStringz, NULL, DONT_RESOLVE_DLL_REFERENCES);
	if (h is null) {
		writeln("Cannot locate Engine.dll");
		return 1;
	}
	scope (exit) FreeLibrary(h);

	FARPROC fp = GetProcAddress(h, "?GetMaxTickRate@UGameEngine@@UAEMXZ".toStringz);
	if (fp is null) {
		writeln("Cannot locate UGameEngine::GetMaxTickRate, is this a valid dll?");
		return 1;
	}

	int addr = (cast(int) fp) - (cast(int) h);
	ubyte[] bytes = cast(ubyte[]) read("Engine.dll");
	if (bytes[addr] != 0xE9) {
		writef("Instruction at 0x%.2X is 0x%.2X instead of 0xE9\nEngine.dll seems to be invalid", addr, bytes[addr]);
		return 1;
	}
	int a = addr + 5; // E9 is a jump relative to the next instruction (5 bytes forward)
	a += reverseBytes(bytes[addr + 1..addr + 5]);
	a += 0x01_A3; // Increment from function start to correct instruction

	int size, ptr; // I should use ImageNtHeader to get this stuff but there were linking errors so oh well
	for (size_t i = 0x02_00; i < 0x03_00; i++) { // Arbitrary range that should always contain .rdata
		if (isRdata(bytes[i..i + 8])) {
			size = reverseBytes(bytes[i + 8..i + 12]);
			ptr = reverseBytes(bytes[i + 12..i + 16]);
		}
	}

	if (size == 0) {
		writeln(".rdata segment could not be found in Engine.dll");
		return 1;
	}

	ubyte[3] constAddr;
	for (size_t i = ptr; i < ptr + size - 1; i++) {
		if (bytes[i] == fps && bytes[i + 1] == 0) {
			i += cast(int) h; // Image base
			constAddr[0] = cast(ubyte) ((i & 0x0000FF) >> 0);
			constAddr[1] = cast(ubyte) ((i & 0x00FF00) >> 8);
			constAddr[2] = cast(ubyte) ((i & 0xFF0000) >> 16);
			break;
		}
	}

	bytes[a + 0] = 0xDF;		 //	DF	FILD 01 ZZ YY XX
//	bytes[a + 1] = 0x05; No change	05
	bytes[a + 2] = constAddr[0]; //	XX
	bytes[a + 3] = constAddr[1]; //	YY
	bytes[a + 4] = constAddr[2]; //	ZZ
//	bytes[a + 5] = 0x10; No change	01

	if (!exists("patched")) mkdir("patched");
	File f = File("patched/Engine.dll", "w");
	f.rawWrite(bytes);
	f.close();
	
	return 0;
}

int reverseBytes(ubyte[] range) {
	int a = range[0];
	a += range[1] << 8;
	a += range[2] << 16;
	a += range[3] << 24;
	return a;
}

bool isRdata(ubyte[] range) {
	return
			range[0] == 0x2E && //.rdata..
			range[1] == 0x72 &&
			range[2] == 0x64 &&
			range[3] == 0x61 &&
			range[4] == 0x74 &&
			range[5] == 0x61 &&
			range[6] == 0x00 &&
			range[7] == 0x00;
}