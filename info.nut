class HeliAI extends AIInfo {
	function GetAuthor()      { return "mmuszkow"; }
	function GetName()        { return "HeliFerry"; }
	function GetDescription() { return "AI using only helicopters and ferries"; }
	function GetVersion()     { return 3; }
	function GetDate()        { return "2016-10-31"; }
	function CreateInstance() { return "HeliFerry"; }
	function GetShortName()   { return "HEFE"; }
    function GetSettings() {
        AddSetting( {
			name = "build_helicopters",
			description = "Build helicopters",
			easy_value = 1,
			medium_value = 1,
			hard_value = 1,
			custom_value = 1,
			flags = AICONFIG_BOOLEAN
		});
        AddSetting( {
			name = "build_ferries",
			description = "Build ferries",
			easy_value = 1,
			medium_value = 1,
			hard_value = 1,
			custom_value = 1,
			flags = AICONFIG_BOOLEAN
		});
    }
}

RegisterAI(HeliAI());
