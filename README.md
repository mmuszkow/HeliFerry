# HeliFerry

Simple OpenTTD AI. It operates 2 types of vehicles which need the least infrastructure:
- *Helicopters* - AI follows the old trick I always used in the past when playing with my siblings: demolish 1 tile directly in the city center, build a heliport there and connect it with the nearest city.
- *Ferries* - I found A*-based pathfinders really slow when working with larger water distances, so I wrote my own 2. One follows a straight line, the other one follows the coast.

Other features include:
- autoreplacing vehicle model when the new, better model appears
- selling unprofitable vehicles
- autoreplacing old vehicles with new ones
