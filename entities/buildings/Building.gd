extends Entity

class_name Building

var cost: Dictionary = {}

var buildTime: float

var stage: int

var buildProgress: float

func upgrade():
	stage += 1
	print("Building upgraded to level: ", stage)

func produce():

    ## Something something give player resource or kinda vibe
    print("Produced a thing")

## Build decrement ???