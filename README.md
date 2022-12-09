# Clusterizer algorithm implementation for Flame

Algorithm takes control over collision detection, components rendering and
components lifecycle and frequency of updates. This allows to gain application
performance by saving additional resources. Also a special 'Layer-components'
are used to compile statical components to single layer but keeping ability to
update layer's image as soon as components parameters are changed.

Algorithm creates "cells" of space dynamically. Each cell could be filled by
components at creation time. Collisions are checked only in current component's cell
and it's neighbours. Moving between cells is cheaper than in QuadTree. Also it become
possible to hide objects from 'out-of-screen' cells and to completely disable game logics
and collision calculation at cells which are very far from player.

Also overlapped hitboxes are grouped into larger 'bounding hitbox' and this allows to 
reduce collision checks if many objects are placed in one cell.  

