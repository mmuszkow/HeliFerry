/* Class which handles selling unprofitable, upgrading and replacing old vehicles. */
class Maintenance {
    
    /* Group for vehicles to be sold. */
    sell_group = [-1, -1];
    
    constructor() {
        /* Autorenew vehicles when old. */
        AICompany.SetAutoRenewMonths(0);
        AICompany.SetAutoRenewStatus(true);
        
        /* Create groups. */
        this.sell_group[0] = AIGroup.CreateGroup(AIVehicle.VT_AIR);
        this.sell_group[1] = AIGroup.CreateGroup(AIVehicle.VT_WATER);
        AIGroup.SetName(this.sell_group[0], AICompany.GetName(AICompany.COMPANY_SELF) + "'s aircrafts to sell");
        AIGroup.SetName(this.sell_group[1], AICompany.GetName(AICompany.COMPANY_SELF) + "'s ships to sell");
        if(!AIGroup.IsValidGroup(this.sell_group[0]) || !AIGroup.IsValidGroup(this.sell_group[1]))
            AILog.Error("Cannot create a vehicles group");
        
    }
}

function Maintenance::SellUnprofitable() {
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
function Maintenance::UpgradeModel(vehicle_type, best_model, cargo) {
    local sent_to_upgrade = 0;
    if(best_model != -1) {
        /* Find the vehicles to be upgraded. */
        local not_best_model = AIVehicleList_DefaultGroup(vehicle_type);
        not_best_model.Valuate(AIVehicle.GetEngineType);
        not_best_model.RemoveValue(best_model);
        not_best_model.Valuate(AIVehicle.GetCapacity, cargo);
        not_best_model.KeepAboveValue(0);
        
        if(not_best_model.Count() > 0) {
            //AILog.Info("Found " + not_best_model.Count() + " upgradable vehicles");
            
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
