class_name Road
extends Path3D
## A dirt road, drawn as a curve. It's invisible in the game. What you see is
## the terrain under it, which tools/build_village.gd paints with dirt, clears
## of grass and trees, and grades to the curve's height: the Y of each curve
## point is how high the road runs there, so a road can climb a hill.
##
## To change a road: select it, move or add curve points with the Path3D
## tools in the 3D view's toolbar, then re-run tools/build_village.gd. (Paint
## from the old position stays behind; touch it up with Terrain3D's paint
## brush if you move a road a long way.)

@export var width := 3.0  # metres of bare dirt; the edges blend into grass
