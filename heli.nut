/* Helicopters part of AI. 
   Builds heliports as close as city center as possible (demolishes building if possible). */

require("utils.nut");

class Heli {
    /* How far from the city center heliport can be. */
    city_center_range = 5;
    /* Min city population to build heliport. */
    min_population = 500;
    /* Max helicopters per heliport. */
    max_vehicles_per_heliport = 3;
    /* Max distance between the cities. */
    max_distance = 300;
    /* Minimal money left after buying something. */
    min_balance = 10000;
    /* New route is build if waiting passengers > this value * capacity of current best vehicle. */
    req_mul = 1.25;
    
    /* Passengers cargo id. */
    _passenger_cargo_id = -1;
    /* Min passengers to open a new route, it's req_mul * best vehicle capacity. */
    _min_passengers = 999999;
    
    constructor() {
        this._passenger_cargo_id = GetPassengersCargo();
    }
}
   
/* Find closest helidepot within specified range. */
function Heli::FindHeliDepot(city_loc, range) {
    local stationlist = AIStationList(AIStation.STATION_AIRPORT);
    stationlist.Valuate(AIStation.GetDistanceManhattanToTile, city_loc);
    stationlist.KeepBelowValue(range);
    for (local station = stationlist.Begin(); stationlist.HasNext(); station = stationlist.Next()) {
        local tile = AIStation.GetLocation(station);
        if(AIAirport.GetAirportType(tile) == AIAirport.AT_HELIDEPOT) {
            //AILog.Info("Using depot " + AIStation.GetName(station));
            return tile;
        }
    }
    return -1;
}

/* Builds a helidepot somewhere between 2 cities. */
function Heli::BuildHeliDepot(city1_loc, city2_loc) {
    local depotarea = AITileList();
    depotarea.AddRectangle(city1_loc, city2_loc);
    depotarea.Valuate(AITile.IsBuildableRectangle, 2, 2);
    depotarea.KeepValue(1);
    
    /* Wait until we have the money. */
    while(AIAirport.IsValidAirportType(AIAirport.AT_HELIDEPOT) &&
          AIAirport.GetPrice(AIAirport.AT_HELIDEPOT) > AICompany.GetBankBalance(AICompany.COMPANY_SELF) - this.min_balance) {}
    
    for (local depot = depotarea.Begin(); depotarea.HasNext(); depot = depotarea.Next()) {
        if(AIAirport.BuildAirport(depot, AIAirport.AT_HELIDEPOT, AIStation.STATION_NEW)) {
            //AILog.Info("Building new helidepot");
            return depot;
        }
    }
    return -1;
}

/* Gets the heliport tile in the city. */
function Heli::FindHeliPort(town_id) {
    local stationlist = AIStationList(AIStation.STATION_AIRPORT);
    stationlist.Valuate(AIStation.GetNearestTown);
    stationlist.KeepValue(town_id);
    for (local station = stationlist.Begin(); stationlist.HasNext(); station = stationlist.Next()) {
        local tile = AIStation.GetLocation(station);
        if(AIAirport.GetAirportType(tile) == AIAirport.AT_HELIPORT) {
            //AILog.Info("Using heliport " + AIStation.GetName(station));
            return tile;
        }
    }
    return -1;
}

function Heli::BuildHeliPort(city_loc) {
    /* 10 tiles from the city center at most. */
    local heliport_tiles = AITileList();
    SafeAddRectangle(heliport_tiles, city_loc, this.city_center_range);
    /* Terrain must be flat. */
    heliport_tiles.Valuate(AITile.GetSlope);
    heliport_tiles.KeepValue(AITile.SLOPE_FLAT);
    /* And the tile must accept passangers. */
    heliport_tiles.Valuate(AITile.GetCargoAcceptance, this._passenger_cargo_id,
                           1, 1, AIAirport.GetAirportCoverageRadius(AIAirport.AT_HELIPORT));
    heliport_tiles.KeepAboveValue(7);
    /* Sort by distance from the city center. */
    heliport_tiles.Valuate(AIMap.DistanceManhattan, city_loc);
    heliport_tiles.Sort(AIList.SORT_BY_VALUE, true);
    
    /* Wait until we have the money. */
    while(AIAirport.IsValidAirportType(AIAirport.AT_HELIPORT) &&
          AIAirport.GetPrice(AIAirport.AT_HELIPORT) > AICompany.GetBankBalance(AICompany.COMPANY_SELF) - this.min_balance) {}
    
    for (local tile = heliport_tiles.Begin(); heliport_tiles.HasNext(); tile = heliport_tiles.Next()) {
        if(!AITile.DemolishTile(tile)) {
            //AILog.Info("Failed to demolish tile (" + AIMap.DistanceManhattan(tile, city_loc) + "): " + AIError.GetLastErrorString());
            continue;
        }
        if(!AIAirport.BuildAirport(tile, AIAirport.AT_HELIPORT, AIStation.STATION_NEW)) {
            switch(AIError.GetLastError()) {
                case AIError.ERR_LOCAL_AUTHORITY_REFUSES:
                    return -1;
                case AIStation.ERR_STATION_TOO_MANY_STATIONS_IN_TOWN:
                    /* We need to have any rating in this town, to avoid it in next loop, so we plant a treeb. */
                    AITile.PlantTree(tile);
                    return -1;
                //default:
                    //AILog.Info("Building heliport failed: " + AIError.GetLastErrorString());
                    
            }
            continue;
        }
        //AILog.Info("Building new heliport " + AIMap.DistanceManhattan(tile, city_loc) + " tiles from the city center");
        return tile;
    }
    
    //AILog.Info("Failed to build the heliport");
    return -1;
}

/* Get available helicopters list. */
function Heli::GetHelicopterModels() {
    local engine_list = AIEngineList(AIVehicle.VT_AIR);
    engine_list.Valuate(AIEngine.GetPlaneType);
    engine_list.KeepValue(AIAirport.PT_HELICOPTER);
    engine_list.Valuate(AIEngine.GetCargoType);
    engine_list.KeepValue(this._passenger_cargo_id);
    return engine_list;
}

/* For finding the best vehicle. */
function HeliModelRating(model) {
    return AIEngine.GetCapacity(model) * AIEngine.GetMaxSpeed(model);
}

function Heli::GetBestHelicopter() {
    local engines = GetHelicopterModels();
    if(engines.Count() == 0)
        return -1;
    
    /* Get the "best" model. */
    engines.Valuate(HeliModelRating);
    engines.Sort(AIAbstractList.SORT_BY_VALUE, false);
    local best = engines.Begin();
    this._min_passengers = floor(this.req_mul * AIEngine.GetCapacity(best));
    return best;
}

function Heli::BuildAndStartHelicopter(heliport1, heliport2) {
    local engine = GetBestHelicopter();
    if(engine == -1)
        return false;
    
    /* Wait until we have the money. */
    while(AIEngine.IsValidEngine(engine) && 
          AIEngine.GetPrice(engine) > AICompany.GetBankBalance(AICompany.COMPANY_SELF) - this.min_balance) {}
    
    local range = 100;
    while(true) {
        /* Find or build the depot, heliport cannot build vehicles. */
        local depot = FindHeliDepot(heliport1, range);
        if(depot == -1) depot = FindHeliDepot(heliport2, range);
        if(depot == -1) depot = BuildHeliDepot(heliport1, heliport2);
        if(depot == -1) {
            AILog.Warning("Failed to build the helidepot, increasing the search range for existing one");
            range *= 2;
            if(range > max(AIMap.GetMapSizeX(), AIMap.GetMapSizeY())) {
                AILog.Error("Failed to find/build a single helidepot on the entire map");
                return false;
            }
        } else {
            /* Buy the most expensive vehicle. */
            local hangar = AIAirport.GetHangarOfAirport(depot);
            local vehicle = AIVehicle.BuildVehicle(hangar, engine);
            if(AIVehicle.IsValidVehicle(vehicle)) {
                /* Schedule path. */
                AIOrder.AppendOrder(vehicle, heliport1, AIOrder.OF_NONE);
                AIOrder.AppendOrder(vehicle, heliport2, AIOrder.OF_NONE);
                //AIVehicle.SetName(vehicle, "");
                AIVehicle.StartStopVehicle(vehicle);
                break;
            } else if(AIError.GetLastError() != AIError.ERR_NOT_ENOUGH_CASH) {
                AILog.Error("Failed to build the helicopter: " + AIError.GetLastErrorString());
                return false;
            }
        }
    }
    
    return true;
}

function Heli::CanTakeMoreHelicopters(heliport) {
    local station_id = AIStation.GetStationID(heliport);
    local passengers = AIStation.GetCargoWaiting(station_id, this._passenger_cargo_id);
    local vehicles = AIVehicleList_Station(station_id).Count();
    return vehicles == 0 || (passengers > this._min_passengers && vehicles < this.max_vehicles_per_heliport);
}

function Heli::AreHelicoptersAllowed() {
    /* Aircrafts disabled. */
    if(AIGameSettings.IsDisabledVehicleType(AIVehicle.VT_AIR))
        return false;
    
    /* Our infrastructure is based on heliports and helidepots. */
    if(!AIAirport.IsValidAirportType(AIAirport.AT_HELIPORT)
        || !AIAirport.IsValidAirportType(AIAirport.AT_HELIDEPOT))
        return false;
    
    /* Max 0 aircrafts. */
    local veh_allowed = AIGameSettings.GetValue("vehicle.max_aircraft");
    if(veh_allowed == 0)
        return false;
    
    /* Current aircrafts < aircrafts limit. */
    local veh_list = AIVehicleList();
    veh_list.Valuate(AIVehicle.GetVehicleType);
    veh_list.KeepValue(AIVehicle.VT_AIR);
    if(veh_list.Count() >= veh_allowed)
        return false;
    
    /* No helicopters available. */
    if(GetBestHelicopter() == -1)
        return false;
    
    return true;
}

function Heli::BuildNewHeliRoutes() {
    if(!AreHelicoptersAllowed())
        return false;

    /* Get the cities with minimal population. */
    local towns = AITownList();
    //towns.Valuate(AITown.GetRating, AICompany.COMPANY_SELF);
    //towns.KeepValue(AITown.TOWN_RATING_NONE);
    towns.Valuate(AITown.GetPopulation);
    towns.KeepAboveValue(this.min_population);
    towns.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
    AILog.Info(towns.Count() + " towns eligible for heliport, min " + this._min_passengers + " passengers to open a new route");
    
    for(local city1 = towns.Begin(); towns.HasNext(); city1 = towns.Next()) {
        /* If there is already a heliport in the city, let's check if it can accept more passengers. */
        local heliport_a = FindHeliPort(city1);
        if(heliport_a != -1 && !CanTakeMoreHelicopters(heliport_a))
            continue;
        
        /* Get cities which are good for connection. */
        local city1_loc = AITown.GetLocation(city1);
        local towns2 = AITownList();
        towns2.RemoveItem(city1);
        towns2.Valuate(AITown.GetPopulation);
        towns2.KeepAboveValue(this.min_population);
        towns2.Valuate(AITown.GetDistanceManhattanToTile, city1_loc);
        towns2.KeepAboveValue(30); /* Cities too close. */
        towns2.KeepBelowValue(this.max_distance); /* Cities too far away. */
        towns2.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);
        
        for(local city2 = towns2.Begin(); towns2.HasNext(); city2 = towns2.Next()) {
            local heliport_b = FindHeliPort(city2);
            /* No more place for new heli in this one. */
            if(heliport_b != -1 && !CanTakeMoreHelicopters(heliport_b))
                continue;

            /* Build heliports. */
            if(heliport_a == -1)
                heliport_a = BuildHeliPort(city1_loc);
            if(heliport_a == -1)
                break;
            if(heliport_b == -1)
                heliport_b = BuildHeliPort(AITown.GetLocation(city2));
            if(heliport_b == -1)
                continue;
        
            /* Build helicopters. */
            if(!AreHelicoptersAllowed())
                return false;
            AILog.Info("Building helicopter route between " + AITown.GetName(city1) + " and " + AITown.GetName(city2));
            if(BuildAndStartHelicopter(heliport_a, heliport_b))
                break;
        }
    }
    
    return true;
}
