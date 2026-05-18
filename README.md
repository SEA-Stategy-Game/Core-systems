# Core-systems

Host:
```
godot.exe --path /path/to/repo -- --showcase-host
````
Client
```
godot.exe --path /path/to/repo -- --showcase-join=127.0.0.1
```

Steps:
1. `Disconnect`at both instances
2. `Host local`at the server window
3. Ìncrement `Player ID`to 1 on server side, press `Apply Player ID` and then `Join local``
4. Hit `Refresh IDs`
5. Client side can now move, gather resource and attack server unit.
    1.  Move: drag over the unit and left click on the map where to go
    2. Gather resource: Hit `Refresh IDs` and then `Attack target`
    3. Attack server unit: Change `Target Entity ID`to `10000`and hit `Attack target`