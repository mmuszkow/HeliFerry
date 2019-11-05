/* Ferries part of AI.
   Builds ferries/hovercrafts. */

require("utils.nut");
require("pairhashset.nut");
require("pathfinder/line.nut");
require("pathfinder/coast.nut");

class Ferry {
    /* Max dock distance from the city center. */
    max_dock_distance = 15;
    /* Open new connections only in cities with this population. */
    min_population = 500;
    /* Max Manhattan distance between 2 cities to open a new connection. */
    max_distance = 300;
    /* Path buoys distance. */
    buoy_distance = 25;
    /* Max connection length. */
    max_path_len = 450;
    /* Minimal money left after buying something. */
    min_balance = 10000;
    /* New route is build if waiting passengers > this value * capacity of current best vehicle. */
    req_mul = 1.25;
    
    /* Passengers cargo id. */
    _passenger_cargo_id = -1;
    /* Min passengers to open a new route, it's req_mul * best vehicle capacity. */
    _min_passengers = 999999;
    /* Pathfinders. */
    _line_pathfinder = StraightLinePathfinder();
    _coast_pathfinder = CoastPathfinder();
    /* Cache of which cities are not connected. */
    _not_connected = null;
    
    constructor() {
        this._passenger_cargo_id = GetPassengersCargo();
        
        /* Dynamic hashset size. */
        local size = AIMap.GetMapSize();
        
        if(size > 4194304) /* bigger than 2048x2048 */
            this._not_connected = PairHashSet(65536);
        else if(size > 1048576) /* bigger than 1024x1024 */
            this._not_connected = PairHashSet(32768);
        else if(size > 262144)  /* bigger than 512x512 */
            this._not_connected = PairHashSet(16384);
        else
            this._not_connected = PairHashSet(8192);
    }
}
   
function Ferry::AreFerriesAllowed() {
    /* Ships disabled. */
    if(AIGameSettings.IsDisabledVehicleType(AIVehicle.VT_WATER))
        return false;

    /* Disabled in AI settings. */
    if(!AIController.GetSetting("build_ferries"))
        return false;
    
    /* Max 0 ships. */
    local veh_allowed = AIGameSettings.GetValue("vehicle.max_ships");
    if(veh_allowed == 0)
        return false;
    
    /* Current ships < ships limit. */
    local veh_list = AIVehicleList();
    veh_list.Valuate(AIVehicle.GetVehicleType);
    veh_list.KeepValue(AIVehicle.VT_WATER);
    if(veh_list.Count() >= veh_allowed)
        return false;
    
    /* No ferries models available. */
    if(GetBestFerry() == -1)
        return false;
    
    return true;
}

/* These 2 needs to be global so we can use them in Valuate. */
function GetCoastTilesCloseToCity(town, range, cargo_id) {
    local city = AITown.GetLocation(town);
    local tiles = AITileList();
    SafeAddRectangle(tiles, city, range);
    tiles.Valuate(AITile.GetClosestTown);
    tiles.KeepValue(town);
    tiles.Valuate(AITile.IsCoastTile);
    tiles.KeepValue(1);
    tiles.Valuate(IsSimpleSlope);
    tiles.KeepValue(1);
    /* Tile must accept passangers. */
    tiles.Valuate(AITile.GetCargoAcceptance, cargo_id, 1, 1,
          AIStation.GetCoverageRadius(AIStation.STATION_DOCK));
    tiles.KeepAboveValue(7); /* as doc says */
    return tiles;
}
function GetCoastTileClosestToCity(town, range, cargo_id) {
    local tiles = GetCoastTilesCloseToCity(town, range, cargo_id);
    if(tiles.IsEmpty())
        return -1;
    
    local city = AITown.GetLocation(town);
    tiles.Valuate(AIMap.DistanceManhattan, city);
    tiles.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);
    return tiles.Begin();
}

function Ferry::FindDock(town) {
    local docks = AIStationList(AIStation.STATION_DOCK);
    docks.Valuate(AIStation.GetNearestTown);
    docks.KeepValue(town);
    if(docks.IsEmpty())
        return -1;
    else
        return AIStation.GetLocation(docks.Begin());
}

function Ferry::BuildDock(town) {
    local coast = GetCoastTilesCloseToCity(town, this.max_dock_distance, this._passenger_cargo_id);
    local city = AITown.GetLocation(town);
    coast.Valuate(AIMap.DistanceManhattan, city);
    coast.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);
    
    /* Wait until we have the money. */
    while(AIMarine.GetBuildCost(AIMarine.BT_DOCK) > AICompany.GetBankBalance(AICompany.COMPANY_SELF) - this.min_balance) {}
    
    for(local tile = coast.Begin(); coast.HasNext(); tile = coast.Next()) {
        if(AIMarine.BuildDock(tile, AIStation.STATION_NEW)) {
            AIStation.SetName(AIStation.GetStationID(tile), AITown.GetName(town) + " Ferry");
            return tile;
        }
    }
    return -1;
}

function Ferry::FindWaterDepot(dock, range) {
    local depots = AIDepotList(AITile.TRANSPORT_WATER);
    depots.Valuate(AIMap.DistanceManhattan, dock);
    depots.KeepBelowValue(range);
    depots.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);
    if(depots.IsEmpty())
        return -1;
    else
        return depots.Begin();
}

function Ferry::BuildWaterDepot(dock, max_distance) {
    local depotarea = AITileList();
    SafeAddRectangle(depotarea, dock, max_distance);
    depotarea.Valuate(AITile.IsWaterTile);
    depotarea.KeepValue(1);
    depotarea.Valuate(AIMap.DistanceManhattan, dock);
    depotarea.KeepAboveValue(4); /* let's not make it too close to docks */
    depotarea.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);
    
    /* Wait until we have the money. */
    while(AIMarine.GetBuildCost(AIMarine.BT_DEPOT) > AICompany.GetBankBalance(AICompany.COMPANY_SELF) - this.min_balance) {}
    
    for(local depot = depotarea.Begin(); depotarea.HasNext(); depot = depotarea.Next()) {
        local x = AIMap.GetTileX(depot);
        local y = AIMap.GetTileY(depot);
        local front = AIMap.GetTileIndex(x, y+1);
        
        /* To avoid building a depot on a river. */
        if(!AITile.IsWaterTile(front) ||
            !AITile.IsWaterTile(AIMap.GetTileIndex(x, y-1)) ||
            !AITile.IsWaterTile(AIMap.GetTileIndex(x-1, y)) ||
            !AITile.IsWaterTile(AIMap.GetTileIndex(x+1, y)))
            continue;
            
        if(AIMarine.BuildWaterDepot(depot, front))
            return depot;
    }
    return -1;
}

/* Buoys are essential for longer paths and also speed up the ship pathfinder. */
function Ferry::GetBuoy(tile) {
    local tiles = AITileList();
    SafeAddRectangle(tiles, tile, 3);
    tiles.Valuate(AIMarine.IsBuoyTile);
    tiles.KeepValue(1);
    if(tiles.IsEmpty()) {
        AIMarine.BuildBuoy(tile);
        return tile;
    } else
        return tiles.Begin();
}

/* Get available ferries models list. */
function Ferry::GetFerryModels() {
    local engine_list = AIEngineList(AIVehicle.VT_WATER);
    engine_list.Valuate(AIEngine.GetCargoType);
    engine_list.KeepValue(this._passenger_cargo_id);
    return engine_list;
}

/* For finding the best vehicle. */
function FerryModelRating(model) {
    return AIEngine.GetCapacity(model) * AIEngine.GetMaxSpeed(model);
}

function Ferry::GetBestFerry() {
    local engines = GetFerryModels();
    if(engines.IsEmpty())
        return -1;
    
    /* Get the "best" model. */
    engines.Valuate(FerryModelRating);
    engines.Sort(AIAbstractList.SORT_BY_VALUE, false);
    local best = engines.Begin();
    this._min_passengers = floor(this.req_mul * AIEngine.GetCapacity(best));
    return best;
}

/* 0 - no existing route, 1 - error, 2 - success */
function Ferry::CloneFerry(dock1, dock2) {    
    /* Check if these 2 docks are indeed served by an existing vehicle. */
    local dock1_vehs = AIVehicleList_Station(AIStation.GetStationID(dock1));
    local dock2_vehs = AIVehicleList_Station(AIStation.GetStationID(dock2));
    dock1_vehs.KeepList(dock2_vehs);
    if(dock1_vehs.IsEmpty())
        return 0;
    
    /* Find the depot where we can clone the vehicle. */
    local depot = FindWaterDepot(dock1, 10);
    if(depot == -1)
        depot = FindWaterDepot(dock2, 10);
    if(depot == -1)
        depot = BuildWaterDepot(dock1, 10);
    if(depot == -1) {
        AILog.Error("Failed to build the water depot: " + AIError.GetLastErrorString());
        return 1;
    }
    
    local vehicle = dock1_vehs.Begin();
    local engine = AIVehicle.GetEngineType(vehicle);
    
    /* Wait until we have the money. */
    while(AIEngine.IsValidEngine(engine) && 
         (AIEngine.GetPrice(engine) > AICompany.GetBankBalance(AICompany.COMPANY_SELF) - this.min_balance)) {}
    
    local cloned = AIVehicle.CloneVehicle(depot, vehicle, true);
    if(!AIVehicle.IsValidVehicle(cloned)) {
        AILog.Error("Failed to clone vehicle: " + AIError.GetLastErrorString());
        return 1;
    }
    
    AIVehicle.StartStopVehicle(cloned);
    return 2;
}

function Ferry::BuildAndStartFerry(dock1, dock2, path) {
    local engine = GetBestFerry();
    if(engine == -1)
        return false;
    
    /* Wait until we have the money. */
    while(AIEngine.IsValidEngine(engine) && 
         (AIEngine.GetPrice(engine) > AICompany.GetBankBalance(AICompany.COMPANY_SELF) - this.min_balance)) {}
    
    /* Find or build the water depot. Don't go too far to avoid finding depot from other lake/sea. */
    local depot = FindWaterDepot(dock1, 10);
    if(depot == -1) {
        depot = BuildWaterDepot(dock1, 10);
        if(depot == -1) {
            AILog.Error("Failed to build the water depot: " + AIError.GetLastErrorString());
            return false;
        }
    }
    
    /* Build buoys every n tiles. */
    local buoys = [];
    for(local i = this.buoy_distance; i<path.len()-this.buoy_distance/2; i += this.buoy_distance)
        buoys.push(GetBuoy(path[i]));
    
    /* Buy the most expensive vehicle. */
    local vehicle = AIVehicle.BuildVehicle(depot, engine);
    if(AIVehicle.IsValidVehicle(vehicle)) {        
        /* Schedule path. */
        if(!AIOrder.AppendOrder(vehicle, dock1, AIOrder.OF_NONE)) {
            AILog.Error("Failed to schedule the ferry: " + AIError.GetLastErrorString());
            AIVehicle.SellVehicle(vehicle);
            return false;
        }
        
        /* Buoys. */
        foreach(buoy in buoys)
            AIOrder.AppendOrder(vehicle, buoy, AIOrder.OF_NONE);
            
        if(!AIOrder.AppendOrder(vehicle, dock2, AIOrder.OF_NONE)) {
            AILog.Error("Failed to schedule the ferry: " + AIError.GetLastErrorString());
            AIVehicle.SellVehicle(vehicle);
            return false;
        }
        
        /* The way back buoys. */
        buoys.reverse();
        foreach(buoy in buoys)
            AIOrder.AppendOrder(vehicle, buoy, AIOrder.OF_NONE);
            
        /* Send for maintanance if too old. This is safer here, cause the vehicle won't get lost
           and also saves us some opcodes. */
        if(    !AIOrder.InsertConditionalOrder(vehicle, 0, 0)
            || !AIOrder.InsertOrder(vehicle, 1, depot, AIOrder.OF_NONE) /* why OF_SERVICE_IF_NEEDED doesn't work? */
            || !AIOrder.SetOrderCondition(vehicle, 0, AIOrder.OC_REMAINING_LIFETIME)
            || !AIOrder.SetOrderCompareFunction(vehicle, 0, AIOrder.CF_MORE_THAN)
            || !AIOrder.SetOrderCompareValue(vehicle, 0, 0)
            ) {
            AILog.Error("Failed to schedule the autoreplacement order: " + AIError.GetLastErrorString());
            AIVehicle.SellVehicle(vehicle);
            return false;
        }
        
        //AIVehicle.SetName(vehicle, "");
        if(!AIVehicle.StartStopVehicle(vehicle)) {
            AILog.Error("Failed to start the ferry: " + AIError.GetLastErrorString());
            AIVehicle.SellVehicle(vehicle);
            return false;
        }
        
        return true;
    } else {
        AILog.Error("Failed to build the ferry: " + AIError.GetLastErrorString());
        return false;
    }
}

function Ferry::BuildFerryRoutes() {
    local ferries_built = 0;
    if(!AreFerriesAllowed())
        return ferries_built;

    /* To avoid exceeding CPU limit in Valuator, we process the towns list in parts */
    local all_towns = AITownList();
    local towns = AIList();
    for(local i=0; i<all_towns.Count(); i+=50) {
        local part = AIList();
        part.AddList(all_towns);
        part.RemoveTop(i);
        part.KeepTop(50);
        part.Valuate(AITown.GetPopulation);
        part.KeepAboveValue(this.min_population);
        part.Valuate(GetCoastTileClosestToCity, this.max_dock_distance, this._passenger_cargo_id);
        part.RemoveValue(-1);
        towns.AddList(part);
    }
    
    //AILog.Info(towns.Count() + " towns eligible for ferry, min " + this._min_passengers + " passengers to open a new route");
    
    for(local town = towns.Begin(); towns.HasNext(); town = towns.Next()) {        
        local dock1 = FindDock(town);
        /* If there is already a dock in the city and there 
           are not many passengers waiting there, there is no point
           in opening a new route. */
        if(dock1 != -1 && AIStation.GetCargoWaiting(AIStation.GetStationID(dock1), this._passenger_cargo_id) < this._min_passengers)
            continue;
        
        /* Find dock or potential place for dock. */
        local coast1 = dock1;
        if(coast1 == -1)
            coast1 = GetCoastTileClosestToCity(town, this.max_dock_distance, this._passenger_cargo_id);
        
        /* Find a city suitable for connection closest to ours. */
        local towns2 = AIList();
        towns2.AddList(towns);
        towns2.RemoveItem(town);
        towns2.Valuate(AITown.GetDistanceManhattanToTile, AITown.GetLocation(town));
        towns2.KeepBelowValue(this.max_distance); /* Cities too far away. */
        towns2.KeepAboveValue(20); /* Cities too close. */
        towns2.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);
        
        for(local town2 = towns2.Begin(); towns2.HasNext(); town2 = towns2.Next()) {
            local dock2 = FindDock(town2);
            /* If there is already a dock in the city and there 
               are not many passengers waiting there, there is no point
               in opening a new route. */
            if(dock2 != -1 && AIStation.GetCargoWaiting(AIStation.GetStationID(dock2), this._passenger_cargo_id) < this._min_passengers)
                continue;
            
            /* If there is already a vehicle servicing this route, clone it, it's much faster. */
            if(dock1 != -1 && dock2 != -1) {
                local clone_res = CloneFerry(dock1, dock2);
                if(clone_res == 2) {
                    AILog.Info("Adding next ferry between " + AITown.GetName(town) + " and " + AITown.GetName(town2));
                    ferries_built++;
                    continue;
                } else if(clone_res == 1) {
                    /* Error. */
                    if(!AreFerriesAllowed())
                        return ferries_built;
                    continue;
                }
            }
                        
            /* Find dock or potential place for dock. */
            local coast2 = dock2;
            if(coast2 == -1)
                coast2 = GetCoastTileClosestToCity(town2, this.max_dock_distance, this._passenger_cargo_id);
            
            /* Too close. */
            if(AIMap.DistanceManhattan(coast1, coast2) < 20)
                continue;

            if(this._not_connected.Contains(coast1, coast2))
                continue;
            
            /* Skip cities that are not connected by water. */
            local path = null;
            if(this._line_pathfinder.FindPath(coast1, coast2, this.max_path_len))
                path = this._line_pathfinder.path;
            else if(this._coast_pathfinder.FindPath(coast1, coast2, this.max_path_len))
                path = this._coast_pathfinder.path;
            else {
                this._not_connected.Add(coast1, coast2);
                continue;
            }
            
            AILog.Info("Building ferry between " + AITown.GetName(town) + " and " + AITown.GetName(town2));
            /* Build docks if needed. */
            if(dock1 == -1)
                dock1 = BuildDock(town);
            if(dock1 == -1) {
                AILog.Error("Failed to build the dock in " + AITown.GetName(town) + ": " + AIError.GetLastErrorString());
                continue;
            }
            if(dock2 == -1)
                dock2 = BuildDock(town2);
            if(dock2 == -1) {
                AILog.Error("Failed to build the dock in " + AITown.GetName(town2) + ": " + AIError.GetLastErrorString());
                continue;
            }
        
            /* Buy and schedule ship. */
            if(BuildAndStartFerry(dock1, dock2, path))
                ferries_built++;
            else if(!AreFerriesAllowed())
                return ferries_built;
        }
    }
            
    //this._not_connected.Debug();
    
    return ferries_built;
}
