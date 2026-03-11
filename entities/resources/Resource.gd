extends Entity

class_name Resource

var amount: int
var maxAmount: int

func harvest():
    if amount > 0:
        amount -= 1
        print ("Resource harvested. Remaing in the node", amount)
    else:
        deplete():

func deplete():
    print("resource is empty")

func regen():
    if amount < maxAmount
        amount += 1