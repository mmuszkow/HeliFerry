require("heli.nut");
require("ferry.nut");
require("maintenance.nut");
require("utils.nut");

class HeliFerry extends AIController {
    constructor() {}
}

function HeliFerry::Save() { return {}; }

function HeliFerry::Start() {
    SetCompanyName();
    
    /* Check if we have anything to do, if not repay the loan and wait. */
    local heli = Heli();
    local ferry = Ferry();
    local maintenance = Maintenance();
    if(!heli.AreHelicoptersAllowed() && !ferry.AreFerriesAllowed()) {
        AILog.Warning("Not possible to build neither helicopters, nor ferries - falling asleep");
        AICompany.SetLoanAmount(0);
    }
    while(!heli.AreHelicoptersAllowed() && !ferry.AreFerriesAllowed()) { this.Sleep(1000); }
    
    /* Get max loan. */
    local loan_limit = AICompany.GetMaxLoanAmount();
    AICompany.SetLoanAmount(loan_limit);
        
    local passengers_cargo = GetPassengersCargo();
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
        local unprofitable_sold = maintenance.SellUnprofitable();
        
        /* Update helicopters when new model comes out (there are 2 models from 1957 and 1997)
           and ferries (there are 3 models from 1926, 1971 and 1968). */
        local upgraded_helis = maintenance.UpgradeModel(AIVehicle.VT_AIR, heli.GetBestHelicopter(), passengers_cargo);
        local upgraded_ferries = maintenance.UpgradeModel(AIVehicle.VT_WATER, ferry.GetBestFerry(), passengers_cargo);

        /* Build statues when nothing better to do, they increase the stations rating. */
        local statues_founded = 0;
        if(new_helis == 0 && new_ferries == 0 && upgraded_helis == 0 && upgraded_ferries == 0)
            statues_founded = BuildStatues();
        
        /* Print summary/ */
        if(new_helis > 1) AILog.Info("New helicopter routes: " + new_helis);
        if(new_ferries > 1) AILog.Info("New ferry routes: " + new_ferries);
        if(unprofitable_sold > 0) AILog.Info("Unprofitable vehicles sold: " + unprofitable_sold);
        if(upgraded_helis > 0) AILog.Info("Helicopters sent for upgrading: " + upgraded_helis);
        if(upgraded_ferries > 0) AILog.Info("Ferries sent for upgrading: " + upgraded_ferries);
        if(statues_founded > 1) AILog.Info("Statues founded: " + statues_founded);
        
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
