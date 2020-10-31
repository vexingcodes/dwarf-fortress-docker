# Dwarf Fortress Docker

Run Dwarf Fortress in an unprivileged Docker container using
[novnc](https://novnc.com/info.html).

Presently, this repository primarily serves as a demonstration of getting a
side-channel audio stream working in novnc using as little custom code as
possible. This is not a complete, robust implementation, but I think it does
prove the concept.

## Usage

Run `./run.sh` in the repository root. It will build the Docker container, and
then run it, exposing ports `8080` and `8081` on localhost. Once the container
is started the script will wait a few seconds (for the VNC server to start up)
and then open the default browser to `http://localhost:8080` which should load
the VNC screen. The screen will be blank for a few seconds, and then Dwarf
Fortress should automatically load. Note, audio will not play until you press a
key after the VNC session has connected. Once you press a key, the audio stream
should start automatically.

## Details

At a high level, this repository is simply a Docker image, built using the
`Dockerfile` in this repository. This image is Debian-based, but it should be
straightforward to port to other base images. No special privileges are required
to run the container, and all processes in the container run as the non-root
user named `df`. Nothing is required to be mounted into the container. The
`run.sh` script automates the building and running of the Docker image.

The container needs to run multiple processes, so we use supervisord as the
init process and it launches all of the background processes. See
`supervisord.conf` for the raw config file. The processes that run are:

* `xvfb` -- The X Virtual FrameBuffer. An in-memory X display server.
* `x11vnc` -- A VNC server that serves the `xvfb` screen on TCP port `5900`.
* `websockify_vnc` -- Serves `x11vnc`, but through a websocket. Also serves the
  files in `/usr/share/novnc` as a webserver. Basically, this process allows the
  `x11vnc` server to be accessible through a browser, using `novnc` as the
  client. This service is exposed on port `8080`.
* `pulseaudio` -- The audio server.
* `audiostream` -- A TCP server listening on port `5901`. This uses
  [ucspi-tcp](https://cr.yp.to/ucspi-tcp.html), a generic TCP client/server
  adapter that can use stdin/stdout for streaming TCP data. When a client
  connects to TCP port `5901`, the `tcpserver` spawns a new process, and the
  stdin/stdout are used for communication between the client and the server. In
  this case, the process that is spawned is a gstreamer pipeline that takes
  audio from the `pulseaudio` server and encodes it as a webm stream.
* `websockify_audio` -- Serves `audiostream`, but through a websocket.
* `dwarffortress` -- The game Dwarf Fortress. It draws to the `xvfb` display and
  transmits audio through the `pulseaudio` server.

Pulseaudio requires two small configuration files to function properly as a
non-root user. Both `default.pa` and `client.conf` are copied to
`/etc/pulseaudio` within the contianer. The `default.pa` file specifies that by
default the `pulseaudio` server should use the unix socket at
`/tmp/pulseaudio.socket` for communication, and should always have an audio sink
available, even if no audio hardware is detected. Since `/tmp` is writable by
the `df` user, this works. The `client.conf` file specifies that by default any
client should use that unix socket as its default server.

Finally, there are the changes required to get `novnc` to connect to and use
this new audio websocket. First, there is a new `webaudio.js` file, written by
GitHub user [no-body-in-particular](https://github.com/no-body-in-particular),
and described in this
[blog post](https://coredump.ws/index.php?dir=code&post=NoVNC_with_audio). This
file is the client-side code that connects to the new websocket and streams the
audio from it. In the `Dockerfile` it can be seen that this file is copied to
`/usr/share/novnc/core/webaudio.js` so it is available among the other `novnc`
core javascript files. Finally, we edit the `vnc_lite.html` file using two sed
commands in the `Dockerfile` (a patch file would probably be more appropriate,
but this works).


```
 && sed -i "/import RFB/a \
      import WebAudio from './core/webaudio.js'" \
    /usr/share/novnc/vnc_lite.html \
 && sed -i "/function connected(e)/a \
      var wa = new WebAudio('ws://localhost:8081/websockify'); \
      document.getElementsByTagName('canvas')[0].addEventListener('keydown', e => { wa.start(); });" \
    /usr/share/novnc/vnc_lite.html
```

The first command edits the file to import the new `webaudio.js` file. The
second command adds new code to the `connected` function that is called when the
VNC session connects. We create a new instance of the `WebAudio` class, and tell
it to start playing audio when a `keydown` event is received by the `canvas`
tag. Presently this is hardcoded to `https://localhost:8081/websockify`. A more
robust implementation would allow the audio URL to be set to different values
depending on the environment.
