# Core-systems


## Running Headless
It's possible to export the project to run headless in the terminal with a custom port number.
The default port is 12345. Keep in mind that for now, the client only connects at 12345.
Here are the instructions:

### MacOS 
* Export the project using the MAC OS preset
* Run `./gameroom.app/Contents/MacOS/Core --headless -- --port <your-port-number"`

### Linux 
* Export the project using the Linux preset
* `chmod +x game_room.x86_64`
* `./my_server.x86_64 --headless --port=<your_port_number>`

### Enabling Redis Integration

To enable features that rely on Redis (like `RedisStateMirror` and `RedisNotificationReceiver`), you must set the `USE_REDIS` environment variable to `true` or `1` before launching the server.

**Example for MacOS:**
```bash
USE_REDIS=true ./gameroom.app/Contents/MacOS/Core --headless -- --port 12345
```

**Example for Linux:**
```bash
USE_REDIS=true ./my_server.x86_64 --headless --port=12345
```
