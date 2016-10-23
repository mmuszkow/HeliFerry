/* Ferries part of AI.
   Builds ferries (hovercrafts). */

require("utils.nut");

class Ferry {
    /* Max dock distance from the city center. */
    max_dock_distance = 20;
    /* Open new connections only in cities with this population. */
    min_population = 500;
    /* Max Manhattan distance between 2 cities to open a new connection. */
    max_distance = 300;
    /* Path buoys distance. */
    buoy_distance = 25;
    /* Max connection length. */
    max_path_len = 450;
    /* Path finder. */
    pathfinder = null;
    /* Minimal money left after buying something. */
    min_balance = 10000;
    
    /* Passengers cargo id. */
    _passenger_cargo_id = -1;
    
    constructor(pf) {
        this.pathfinder = pf;
        this._passenger_cargo_id = GetPassengersCargo();
    }
}
   
function Ferry::AreFerriesAllowed() {
    /* Ships disabled. */
    if(AIGameSettings.IsDisabledVehicleType(AIVehicle.VT_WATER))
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
    tiles.Valuate(AITile.IsCoastTile);
    tiles.KeepValue(1);
    tiles.Valuate(IsSimpleSlope);
    tiles.KeepValue(1);
    tiles.Valuate(AITile.GetClosestTown);
    tiles.KeepValue(town);
    /* Tile must accept passangers. */
    tiles.Valuate(AITile.GetCargoAcceptance, cargo_id, 1, 1,
                  AIStation.GetCoverageRadius(AIStation.STATION_DOCK));
    tiles.KeepAboveValue(7); /* as doc says */
    return tiles;
}
function GetCoastTileClosestToCity(town, range, cargo_id) {
    local tiles = GetCoastTilesCloseToCity(town, range, cargo_id);
    if(tiles.Count() == 0)
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
    if(docks.Count() == 0)
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
    if(depots.Count() == 0)
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
        local front = AIMap.GetTileIndex(AIMap.GetTileX(depot), AIMap.GetTileY(depot)+1);
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
    if(tiles.Count() == 0) {
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
    if(engines.Count() == 0)
        return -1;
    
    /* Get the "best" model. */
    engines.Valuate(FerryModelRating);
    engines.Sort(AIAbstractList.SORT_BY_VALUE, false);
    return engines.Begin();
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
    for(local i = this.buoy_distance; i<path.len()-this.buoy_distance; i += this.buoy_distance) {
        buoys.push(GetBuoy(path[i]));
    }
    
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
        
        //AIVehicle.SetName(vehicle, "");
        AIVehicle.StartStopVehicle(vehicle);
        return true;
    } else {
        AILog.Error("Failed to build the ferry: " + AIError.GetLastErrorString());
        return false;
    }
}

function Ferry::BuildFerryRoutes() {
    if(!AreFerriesAllowed())
        return false;

    local towns = AITownList();
    towns.Valuate(AITown.GetPopulation);
    towns.KeepAboveValue(this.min_population);
    towns.Valuate(GetCoastTileClosestToCity, this.max_dock_distance, this._passenger_cargo_id);
    towns.RemoveValue(-1);
    
    AILog.Info(towns.Count() + " towns eligible for ferry");
    
    for(local town = towns.Begin(); towns.HasNext(); town = towns.Next()) {        
        local dock1 = FindDock(town);
        /* If there is already a dock in the city and there 
           are not many passengers waiting there, there is no point
           in opening a new route. */
        if(dock1 != -1 && AIStation.GetCargoWaiting(AIStation.GetStationID(dock1), this._passenger_cargo_id) < 150)
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
            if(dock2 != -1 && AIStation.GetCargoWaiting(AIStation.GetStationID(dock2), this._passenger_cargo_id) < 150)
                continue;
            
            /* Find dock or potential place for dock. */
            local coast2 = dock2;
            if(coast2 == -1)
                coast2 = GetCoastTileClosestToCity(town2, this.max_dock_distance, this._passenger_cargo_id);
            
            /* Too close. */
            if(AIMap.DistanceManhattan(coast1, coast2) < 20)
                continue;
            
            /* TODO: if docks exist, copy the existing route instead of searching path again. */
            
            /* Skip cities that are not connected by water. */
            if(!this.pathfinder.FindPath(coast1, coast2, this.max_path_len))
                continue;
            
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
            if(!AreFerriesAllowed())
                return false;
            BuildAndStartFerry(dock1, dock2, this.pathfinder.path);
        }
    }
    return true;
}