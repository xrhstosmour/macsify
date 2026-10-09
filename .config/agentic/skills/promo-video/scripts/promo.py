#!/usr/bin/env python3
"""Renders scenes into an mp4 with a headless Chromium browser and ffmpeg, standard library only.

Usage: promo.py <spec> <out.mp4>

Spec lines, paths relative to the spec file, a hash starts a comment:
  size 1920x1080
  fps 30
  transition fade 0.8
  fadeout 0.6
  scene scene1.html 5
  layer badge.html 5.4 3.6 slide

A scene or layer ending in .html is captured to a PNG next to it first, layers with a transparent
background. A .png is used as is. Set CHROME to a browser binary to override the lookup.
Runs on macOS, Linux, and Windows.
"""
import os
import shutil
import subprocess
import sys
from pathlib import Path


def find_browser():
    if os.environ.get("CHROME"):
        return os.environ["CHROME"]
    candidates = [
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        "/Applications/Chromium.app/Contents/MacOS/Chromium",
        "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
    ]
    for variable in ("ProgramFiles", "ProgramFiles(x86)", "LOCALAPPDATA"):
        base = os.environ.get(variable)
        if base:
            candidates += [
                f"{base}/Google/Chrome/Application/chrome.exe",
                f"{base}/Microsoft/Edge/Application/msedge.exe",
            ]
    for candidate in candidates:
        if os.path.isfile(candidate):
            return candidate
    for name in ("google-chrome", "google-chrome-stable", "chromium", "chromium-browser", "microsoft-edge"):
        found = shutil.which(name)
        if found:
            return found
    sys.exit("No Chrome, Chromium, or Edge found, install one or set CHROME")


def capture(browser, source, size, transparent):
    # A separate name keeps a real screenshot called `<scene>.png` next to the scene safe.
    png = source.with_name(f"{source.stem}.capture.png")
    # A stylesheet, font, or image next to or below the scene can change without its HTML changing.
    # The captures themselves and the spec, a .txt file, are left out.
    captures = {path.with_name(f"{path.stem}.capture.png") for path in source.parent.glob("*.html")}
    newest = max(path.stat().st_mtime for path in source.parent.rglob("*")
                 if path.is_file() and path not in captures and path.suffix != ".txt")
    if png.exists() and png.stat().st_mtime >= newest:
        return png
    png.unlink(missing_ok=True)
    arguments = [browser, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                 f"--window-size={size.replace('x', ',')}", f"--screenshot={png}", source.as_uri()]
    if transparent:
        arguments.insert(4, "--default-background-color=00000000")
    # Chrome prints harmless errors on stderr, the PNG check decides success and stderr explains a failure.
    try:
        result = subprocess.run(arguments, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True, timeout=120)
    except subprocess.TimeoutExpired:
        sys.exit(f"capture timed out: {source}")
    if not png.exists() or png.stat().st_size == 0:
        sys.exit(f"capture failed: {source}\n{result.stderr[-500:]}")
    return png


def parse(spec_path):
    settings = {"size": "1920x1080", "fps": 30, "transition": "fade", "tduration": 0.8, "fadeout": 0.0}
    scenes, layers = [], []
    for raw in spec_path.read_text().splitlines():
        words = raw.split("#")[0].split()
        if not words:
            continue
        keyword, rest = words[0], words[1:]
        try:
            if keyword == "size":
                settings["size"] = rest[0]
            elif keyword == "fps":
                settings["fps"] = int(rest[0])
            elif keyword == "transition":
                settings["transition"], settings["tduration"] = rest[0], float(rest[1])
            elif keyword == "fadeout":
                settings["fadeout"] = float(rest[0])
            elif keyword == "scene":
                scenes.append((rest[0], float(rest[1])))
            elif keyword == "layer":
                layers.append((rest[0], float(rest[1]), float(rest[2]), rest[3] if len(rest) > 3 else "fade"))
            else:
                sys.exit(f"unknown spec line: {raw}")
        except (IndexError, ValueError):
            sys.exit(f"bad spec line: {raw}")
    if not scenes:
        sys.exit("spec has no scene lines")
    if len(scenes) > 1 and any(seconds <= settings["tduration"] for _, seconds in scenes):
        sys.exit(f"every scene must be longer than the {settings['tduration']:g}s transition")
    return settings, scenes, layers


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    spec_path, output = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
    ffmpeg = shutil.which("ffmpeg") or sys.exit("ffmpeg not found")
    settings, scenes, layers = parse(spec_path)
    size, fps = settings["size"], settings["fps"]
    transition, tduration, fadeout = settings["transition"], settings["tduration"], settings["fadeout"]
    browser = None

    def resolve(name, transparent):
        nonlocal browser
        path = spec_path.parent / name
        if not path.exists():
            sys.exit(f"missing {path}")
        if path.suffix == ".html":
            browser = browser or find_browser()
            return capture(browser, path, size, transparent)
        return path

    inputs, graph = [], []
    for index, (name, seconds) in enumerate(scenes):
        inputs += ["-i", str(resolve(name, False))]
        # One input frame, zoompan creates all the output frames, a looped input would multiply them.
        zoom = "min(zoom+0.0007,1.1)" if index % 2 == 0 else "max(1.1-on*0.0007,1.0)"
        graph.append(f"[{index}:v]zoompan=z='{zoom}':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)'"
                     f":d={round(seconds * fps)}:s={size}:fps={fps},format=yuv420p[s{index}]")

    # After joining k+1 clips the length is the sum of their durations minus k transitions.
    current, length = "s0", scenes[0][1]
    for index in range(1, len(scenes)):
        graph.append(f"[{current}][s{index}]xfade=transition={transition}:duration={tduration}"
                     f":offset={length - tduration:g}[x{index}]")
        current, length = f"x{index}", length + scenes[index][1] - tduration

    input_index = len(scenes)
    for name, start, seconds, mode in layers:
        inputs += ["-framerate", str(fps), "-loop", "1", "-t", f"{seconds:g}", "-i", str(resolve(name, True))]
        graph.append(f"[{input_index}:v]format=rgba,fade=t=in:st=0:d=0.5:alpha=1,setpts=PTS+{start:g}/TB[l{input_index}]")
        if mode == "slide":
            position = f"x='if(lt(t-{start:g},0.8),W*pow(1-(t-{start:g})/0.8,3),0)':y=0:eval=frame"
        else:
            position = "x=0:y=0"
        graph.append(f"[{current}][l{input_index}]overlay={position}:eof_action=pass[o{input_index}]")
        current, input_index = f"o{input_index}", input_index + 1

    if fadeout > 0:
        graph.append(f"[{current}]fade=t=out:st={length - fadeout:g}:d={fadeout:g},format=yuv420p[v]")
    else:
        graph.append(f"[{current}]format=yuv420p[v]")

    output.parent.mkdir(parents=True, exist_ok=True)
    command = [ffmpeg, "-hide_banner", "-loglevel", "error", "-y", *inputs, "-filter_complex", ";".join(graph),
               "-map", "[v]", "-t", f"{length:g}", "-c:v", "libx264", "-crf", "18", "-preset", "medium",
               "-movflags", "+faststart", str(output)]
    subprocess.run(command, check=True)
    print(f"rendered {output}, {length:g}s")


if __name__ == "__main__":
    main()
