require("heli.nut");
require("ferry.nut");

class HeliFerry extends AIController {
    /* These vehicles will be sold. */
    sell_group = [-1, -1];
    /* Max age months left before replacing. */
    max_age_left = 3;
    
    constructor() {}
}

function HeliFerry::Save() { return {}; }

function HeliFerry::Start() {
    SetCompanyName();
    
    /* Create groups. */
    this.sell_group[0] = AIGroup.CreateGroup(AIVehicle.VT_AIR);
    this.sell_group[1] = AIGroup.CreateGroup(AIVehicle.VT_WATER);
    AIGroup.SetName(this.sell_group[0], "Helicopters to sell");
    AIGroup.SetName(this.sell_group[1], "Ferries to sell");
    if(!AIGroup.IsValidGroup(this.sell_group[0]) || !AIGroup.IsValidGroup(this.sell_group[1]))
        AILog.Error("Cannot create a vehicles group");
    
    /* Get max loan. */
    local loan_limit = AICompany.GetMaxLoanAmount();
    AICompany.SetLoanAmount(loan_limit);
    
    /* Autorenew vehicles when old. */
    AICompany.SetAutoRenewMonths(-this.max_age_left);
    AICompany.SetAutoRenewStatus(true);
    
    local heli = Heli();
    local ferry = Ferry();
    while(true) {
        /* Build heliports first as they are the most profitable 
           and there is a limit of airports per city. */
        local new_helis = heli.BuildNewHeliRoutes();
        
        /* Repay the loan, after building all heliports we should have a lot of money. */
        if(AICompany.GetBankBalance(AICompany.COMPANY_SELF) > loan_limit)
            AICompany.SetLoanAmount(0);
        
        /* Build ferries, they are not as profitable, but usually other AIs 
           don't build water units so we can still have some space here. 
           We may get also above the aircrafts limit. */
        local new_ferries = ferry.BuildFerryRoutes();
        
        /* Sell unprofiltable vehicles. */
        local unprofitable_sold = SellUnprofitable();
        
        /* Update helicopters when new model comes out (there are 2 models from 1957 and 1997)
           and ferries (there are 3 models from 1926, 1971 and 1968). */
        local upgraded_helis = UpgradeModel(heli.GetBestHelicopter(), AIVehicle.VT_AIR);
        local upgraded_ferries = UpgradeModel(ferry.GetBestFerry(), AIVehicle.VT_WATER);
        
        /* Replace too old vehicles. */
        local old_replaced = ReplaceOld();
        
        /* Build statues when nothing better to do, they increase the stations rating. */
        local statues_founded = 0;
        if(new_helis == 0 && new_ferries == 0 && upgraded_helis == 0 && upgraded_ferries == 0 && old_replaced == 0)
            statues_founded = BuildStatues();
        
        /* Print summary/ */
        if(new_helis > 0) AILog.Info("New helicopter routes: " + new_helis);
        if(new_ferries > 0) AILog.Info("New ferry routes: " + new_ferries);
        if(unprofitable_sold > 0) AILog.Info("Unprofitable vehicles sold: " + unprofitable_sold);
        if(upgraded_helis > 0) AILog.Info("Helicopters sent for upgrading: " + upgraded_helis);
        if(upgraded_ferries > 0) AILog.Info("Ferries sent for upgrading: " + upgraded_ferries);
        if(old_replaced > 0) AILog.Info("Old vehicles sent for replacing: " + old_replaced);
        if(statues_founded > 0) AILog.Info("Statues founded: " + statues_founded);
        
        this.Sleep(50);
    }
}
 
function HeliFerry::SetCompanyName() {
    if(!AICompany.SetName("HeliFerry")) {
        local i = 2;
        while(!AICompany.SetName("HeliFerry #" + i)) {
            i = i + 1;
            if(i > 255) break;
        }
    }
    
    if(AICompany.GetPresidentGender(AICompany.COMPANY_SELF) == AICompany.GENDER_MALE)
        AICompany.SetPresidentName("Mr. Moshe Goldbaum");
    else
        AICompany.SetPresidentName("Mrs. Rivkah Blumfeld");
}

function HeliFerry::SellUnprofitable() {
    local sold = 0;
    
    /* Sell unprofitable in depots. */
    local unprofitable = AIVehicleList_Group(this.sell_group[0]);
    unprofitable.AddList(AIVehicleList_Group(this.sell_group[1]));
    for(local vehicle = unprofitable.Begin(); unprofitable.HasNext(); vehicle = unprofitable.Next()) {
        if(AIVehicle.IsStoppedInDepot(vehicle))
            if(AIVehicle.SellVehicle(vehicle))
                sold++;
            else
                AILog.Error("Failed to sell unprofitable vehicle: " + AIError.GetLastErrorString());
    }
        
    /* Find unprofitable. */
    unprofitable = AIVehicleList_DefaultGroup(AIVehicle.VT_WATER);
    unprofitable.AddList(AIVehicleList_DefaultGroup(AIVehicle.VT_AIR));
    unprofitable.Valuate(AIVehicle.GetProfitLastYear);
    unprofitable.KeepBelowValue(0);
    unprofitable.Valuate(AIVehicle.GetProfitThisYear);
    unprofitable.KeepBelowValue(0);
    unprofitable.Valuate(AIVehicle.GetAge);
    unprofitable.KeepAboveValue(1095); /* 3 years old minimum */
    unprofitable.Valuate(AIVehicle.IsValidVehicle);
    unprofitable.KeepValue(1);
    for(local vehicle = unprofitable.Begin(); unprofitable.HasNext(); vehicle = unprofitable.Next()) {
        if(AIVehicle.SendVehicleToDepot(vehicle)) {
            /* We remove them from default group to avoid looping the "send to depot" order. */
            switch(AIVehicle.GetVehicleType(vehicle)) {
                case AIVehicle.VT_AIR:
                    AIGroup.MoveVehicle(this.sell_group[0], vehicle);
                    break;
                case AIVehicle.VT_WATER:
                    AIGroup.MoveVehicle(this.sell_group[1], vehicle);
                    break;
            }
        } else
            AILog.Error("Failed to send unprofitable vehicle to depot: " + AIError.GetLastErrorString());
    }
    
    return sold;
}

/* Replaces with best model, this function works only if we have 1 "type" of vehicle (e.g. helicopter or ferry). */
function HeliFerry::UpgradeModel(best_model, vehicle_type) {
    local sent_to_upgrade = 0;
    if(best_model != -1) {
        /* Find the vehicles to be upgraded. */
        local not_best_model = AIVehicleList_DefaultGroup(vehicle_type);
        not_best_model.Valuate(AIVehicle.GetEngineType);
        not_best_model.RemoveValue(best_model);
        if(not_best_model.Count() > 0) {
            AILog.Info("Found " + not_best_model.Count() + " upgradable vehicles");
            
            /* We need to have money. */
            local min_balance = AICompany.GetAutoRenewMoney(AICompany.COMPANY_SELF);
            local balance = AICompany.GetBankBalance(AICompany.COMPANY_SELF);
            local double_price = 2 * AIEngine.GetPrice(best_model);
            
            for(local vehicle = not_best_model.Begin(); not_best_model.HasNext(); vehicle = not_best_model.Next()) {
                AIGroup.SetAutoReplace(AIGroup.GROUP_DEFAULT, AIVehicle.GetEngineType(vehicle), best_model);
                /* The company needs to have more money than (autoreplace money limit) + 2 * (price for new vehicles). */
                if(balance < double_price + min_balance)
                    break;
                balance -= double_price;
                /* We need to send them to depots to be replaced. */
                if(!AIOrder.IsGotoDepotOrder(vehicle, AIOrder.ORDER_CURRENT))
                    if(AIVehicle.SendVehicleToDepotForServicing(vehicle))
                        sent_to_upgrade++;
                    else
                        AILog.Error("Failed to send the vehicle for servicing: " + AIError.GetLastErrorString());
            }
        }
    }
    return sent_to_upgrade;
}

function HeliFerry::ReplaceOld() {
    local sent_to_replace = 0;
    
    /* Find the vehicles to be upgraded. */
    local old = AIVehicleList_DefaultGroup(AIVehicle.VT_AIR);
    old.AddList(AIVehicleList_DefaultGroup(AIVehicle.VT_WATER));
    old.Valuate(AIVehicle.GetAgeLeft);
    old.KeepBelowValue(this.max_age_left * 30);
    if(old.Count() > 0) {
        /* We need to have money. */
        local min_balance = AICompany.GetAutoRenewMoney(AICompany.COMPANY_SELF);
        local balance = AICompany.GetBankBalance(AICompany.COMPANY_SELF);
            
        for(local vehicle = old.Begin(); old.HasNext(); vehicle = old.Next()) {
            /* The vehicle model may not be available any more. */
            local engine = AIVehicle.GetEngineType(vehicle);
            if(AIEngine.IsValidEngine(engine)) {
                /* Let's keep a safe amount of money left. */
                local double_price = 2 * AIEngine.GetPrice(engine);
                if(balance < double_price + min_balance)
                    break;
                balance -= double_price;
                
                /* We need to send them to depots to be replaced. */
                if(!AIOrder.IsGotoDepotOrder(vehicle, AIOrder.ORDER_CURRENT))
                    if(AIVehicle.SendVehicleToDepotForServicing(vehicle))
                        sent_to_replace++;
                    else
                        AILog.Error("Failed to send the vehicle for servicing: " + AIError.GetLastErrorString());
            }
        }
    }
    
    return sent_to_replace;
}

/* Build statues in the cities we have any stations. */
function HeliFerry::BuildStatues() {
    local founded = 0;
    
    if(AICompany.GetBankBalance(AICompany.COMPANY_SELF) < 10000000)
        return founded;
    
    local towns = AITownList();
    towns.Valuate(AITown.GetRating, AICompany.COMPANY_SELF);
    towns.RemoveValue(AITown.TOWN_RATING_NONE);
    towns.Valuate(AITown.HasStatue);
    towns.KeepValue(0);
    towns.Valuate(AITown.IsActionAvailable, AITown.TOWN_ACTION_BUILD_STATUE);
    towns.KeepValue(1);
    
    for(local town = towns.Begin(); towns.HasNext(); town = towns.Next()) {
        if(AICompany.GetBankBalance(AICompany.COMPANY_SELF) < 10000000)
            return founded;
        if(AITown.PerformTownAction(town, AITown.TOWN_ACTION_BUILD_STATUE)) {
            AILog.Info("Building statue in " + AITown.GetName(town));
            founded++;
        } else
            AILog.Error("Failed to build statue in " + AITown.GetName(town) + ": " + AIError.GetLastErrorString());
    }
    
    return founded;
}
