extends Entity

var type: int

# Stat modifiers tied to the given equipment
var attackModifier: float
var speedModifier: float
var rangeModifier: float

func getMods() -> Dictionary:
    return {
        "attack": attackModifier,
		"speed": speedModifier,
		"range": rangeModifier 
    }