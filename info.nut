class HeliAI extends AIInfo {
	function GetAuthor()      { return "mmuszkow"; }
	function GetName()        { return "HeliFerry"; }
	function GetDescription() { return "AI using only helicopters and ferries"; }
	function GetVersion()     { return 2; }
	function GetDate()        { return "2016-10-28"; }
	function CreateInstance() { return "HeliFerry"; }
	function GetShortName()   { return "HEFE"; }
}

RegisterAI(HeliAI());
