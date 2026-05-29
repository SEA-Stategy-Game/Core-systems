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
