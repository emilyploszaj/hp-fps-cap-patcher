import core.sys.windows.windows;

import std.conv;
import std.file;
import std.stdio;
import std.string;

ubyte fps;

int main() {
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

	FARPROC fp2 = GetProcAddress(h, "?WrappedPrint@UCanvas@@AAAXW4ERenderStyle@@AAH1PAVUFont@@HPBGHH@Z".toStringz);
	if (fp2 is null) {
		writeln("Cannot locate UCanvas::WrappedPrint, is this a valid dll?");
		return 1;
	}

	int addr = (cast(int) fp) - (cast(int) h);
	int addr2 = (cast(int) fp2) - (cast(int) h);
	ubyte[] bytes = cast(ubyte[]) read("Engine.dll");
	if (bytes[addr] != 0xE9) {
		writef("Instruction at 0x%.2X is 0x%.2X instead of 0xE9\nEngine.dll seems to be invalid", addr, bytes[addr]);
		return 1;
	}
	if (bytes[addr2] != 0xE9) {
		writef("Instruction at 0x%.2X is 0x%.2X instead of 0xE9\nEngine.dll seems to be invalid", addr2, bytes[addr2]);
		return 1;
	}
	int a = addr + 5; // E9 is a jump relative to the next instruction (5 bytes forward)
	a += reverseBytes(bytes[addr + 1..addr + 5]);
	a += 0x01_A3; // Increment from function start to correct instruction

	int b = addr2 + 5; // E9 is a jump relative to the next instruction (5 bytes forward)
	b += reverseBytes(bytes[addr2 + 1..addr2 + 5]);
	b += 0x93; // Increment from function start to correct instruction
	//writefln("%.2X", b);
	bytes[b] = 0x70; // Set to big font if using big or large font instead of medium font

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

	bytes.writeBytes(a, (cast(ubyte[]) [
		0xDF, 0x05
	]) ~ constAddr);

	if (!exists("patched")) mkdir("patched");
	File f = File("patched/Engine.dll", "w");
	f.rawWrite(bytes);
	f.close();
	writeln("Engine.dll has been patched to natively cap to ", fps, " fps");
	
	return patchRender();
}

int patchRender() {
	HMODULE h = LoadLibraryExA("Render.dll".toStringz, NULL, DONT_RESOLVE_DLL_REFERENCES);
	if (h is null) {
		writeln("Cannot locate Render.dll");
		return 1;
	}
	scope (exit) FreeLibrary(h);

	FARPROC fp = GetProcAddress(h, "?DrawStats@URender@@QAEXPAUFSceneNode@@@Z".toStringz);
	if (fp is null) {
		writeln("Cannot locate URender::DrawStats, is this a valid dll?");
		return 1;
	}

	int addr = (cast(int) fp) - (cast(int) h);
	ubyte[] bytes = cast(ubyte[]) read("Render.dll");
	if (bytes[addr] != 0xE9) {
		writef("Instruction at 0x%.2X is 0x%.2X instead of 0xE9\nRender.dll seems to be invalid", addr, bytes[addr]);
		return 1;
	}
	int a = addr + 5; // E9 is a jump relative to the next instruction (5 bytes forward)
	a += reverseBytes(bytes[addr + 1..addr + 5]);

	//import std.algorithm: each;
	//writeln();
	//bytes[a..a + 1000].each!(b => writef("%.2X", b));
	//writeln();

	a += 0x01_4c; // Increment from function start to correct instruction

	bytes[a] = 0x78; // Change instruction from jge to js to remove smoothing

	bool foundOffset = false;

	for (int i = 0; i < 400; i++) {
		if (isDrawStatsDataAnchor(bytes[a + i..a + i + 6])) {
			a += i;
			foundOffset = true;
			break;
		}
	}

	if (!foundOffset) {
		writeln("Could not find instruction anchor point, Render.dll seems to be invalid");
		return 1;
	}

	bytes[a - 0x53] = 0x85; // Change je to jne to invert when the stat should be shown, true by default

	bytes.writeBytes(a - 0x44, (cast(ubyte[]) [ // Change x pos from center of screen to 40 pixels from the right
		0x8B, 0x93, 0xAC, 0x00, 0x00, 0x00,	// mov edx, DWORD PTR [ebx+0xac]
		0x83, 0xE8, 0x2C, 					// sub eax, 44
		0x90								// nop
	]));

	bytes[a - 0x35] = 20; // Change y pos from 10 above the bottom to 20 above the bottom

	float fl = 1f;
	ubyte[4] timeToFps = *(cast(ubyte[4]*) (&fl));

	int textConst = reverseBytes(bytes[a + 0x36..a + 0x3A]) - cast(int) h;
	bytes.writeBytes(textConst, (cast(ubyte[]) [
		0x25, 0x00,	// %
		0x32, 0x00,	// 5
		0x2E, 0x00,	// .
		0x31, 0x00,	// 1
		0x66, 0x00,	// f
		0x00, 0x00,	// \0
		0x46, 0x00,	// F
		0x50, 0x00,	// P
		0x53, 0x00,	// S
		0x00, 0x00,	// \0
	]) ~ timeToFps);
	
	textConst += (cast(int) h) + 20;
	ubyte[4] constAddr = *(cast(ubyte[4]*) &textConst);

	a += 0x2C;
	bytes.writeBytes(a, (cast(ubyte[]) [
		0xD8, 0x3D
	]) ~ constAddr);

	bytes[a - 0x01] += 8; // Point to large font instead of small

	bytes[a + 0x0F] = 0; // Un-center the text

	File f = File("patched/Render.dll", "w");
	f.rawWrite(bytes);
	f.close();
	writeln("Render.dll has been patched to natively display framerate");

	return 0;
}

// TODO can be accomplished with pointer casting, preferable?
int reverseBytes(ubyte[] range) {
	int a = range[0];
	a += range[1] << 8;
	a += range[2] << 16;
	a += range[3] << 24;
	return a;
}

void writeBytes(ref ubyte[] bytes, int addr, ubyte[] toWrite) {
	for (int i = 0; i < toWrite.length; i++) {
		bytes[addr + i] = toWrite[i];
	}
}

// TODO genericize comparing a range to a compile time constant
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

// ditto
bool isDrawStatsDataAnchor(ubyte[] range) {
	return
			range[0] == 0x83 && //sub esp,0x8
			range[1] == 0xEC &&	//fild DWORD PTR [eax+0xc]
			range[2] == 0x08 &&
			range[3] == 0xDB &&
			range[4] == 0x40 &&
			range[5] == 0x0C;
}