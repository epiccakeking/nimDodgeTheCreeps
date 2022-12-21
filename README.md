# Dodge the Creeps Nim

This is a port of [Dodge the Creeps](https://docs.godotengine.org/en/latest/getting_started/first_2d_game/index.html) to Nim/SDL2.

## Running
With nimble:
1. Clone the repository
2. cd into the repository
3. Use nimble run

In commands:
```
git clone https://github.com/epiccakeking/nimDodgeTheCreeps.git
cd nimDodgeTheCreeps
nimble run
```

## Limitations
* For simplicity collisions are just circles instead of implementing capsules
* Game over/Restart menu is keyboard only

## Copying

The code is written by me, though with heavy referencing of the original Godot version, and some referencing of Nim's SDL2 Pong example to figure out how to structure the project. 

Copyright information from the original README:

`art/House In a Forest Loop.ogg` Copyright &copy; 2012 [HorrorPen](https://opengameart.org/users/horrorpen), [CC-BY 3.0: Attribution](http://creativecommons.org/licenses/by/3.0/). Source: https://opengameart.org/content/loop-house-in-a-forest

Images are from "Abstract Platformer". Created in 2016 by kenney.nl, [CC0 1.0 Universal](http://creativecommons.org/publicdomain/zero/1.0/). Source: https://www.kenney.nl/assets/abstract-platformer

Font is "Xolonium". Copyright &copy; 2011-2016 Severin Meyer <sev.ch@web.de>, with Reserved Font Name Xolonium, SIL open font license version 1.1. Details are in `fonts/LICENSE.txt`.
