# Harry Potter FPS Cap Patcher
The Harry Potter and the Philosopher's Stone and Harry Potter and the Chamber of Secrets PC video games don't natively cap their frame rate. A developer *attempted* to do this, but instead they just made the game run fast above 200 FPS by making 1/200th of a frame the minimum amount of time calculated in a tick. Whoops. This is not ideal for speedrunning because above 200 FPS the games will simply become faster. In order to have competitive speedruns, the games need to be capped to a value under 200, and as stated the game doesn't support this. But the engine does!

A function in the Engine.dll file for HP1 and HP2 is called to get what to cap the frame rate at (``UGameEngine::GetMaxTickRate``) but returns 0, signifying no capping should be done. So this program modifies the dll to return a value that is not 0.

## Building
hp-fps-cap-patcher is written in D and is built with dub, the standard package manager included with [dmd](https://dlang.org/download.html), D's reference compiler. The program expects an ``Engine.dll`` from either HP1 or HP2 in the root directory to use as a base, building a patched version in ``patched/Engine.dll``. The cap for FPS is prompted on build.

## Procedure
This patch works by replacing the following instruction in ``Engine.dll``:

```D9 05 98 45 47 10```

This instruction loads a float stored at ``10474598`` to be returned from the function, the value stored at ``10474598`` is zero. The patch replaces this instruction with the following:

```DF 05 XX YY ZZ 10```

This loads an integer stored at 10ZZYYXX. The address has to point to a desired integer value, and must already exist in the dll. Fortunately, every value from 0 to 255 is readily present in all versions of ``Engine.dll``. This address is generated from the ``.rdata`` segment of the provided dll on build.