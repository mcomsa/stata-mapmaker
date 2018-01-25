*===============================================================================
* Maptile 2 - better maptiles using Jimmy Narang's D3JS scripts
* Requirements:
*    1. Python installed and 'python' as system env variable (tested on 3.5.2)
*       (e.g. 'python' at the command line should launch the Python interpreter)
*    2. Dropbox/Ado folder synced locally
*    3. Global $dropbox pointed to local dropbox directory (set in profile.do)
* Last updated: 03/01/2017
*===============================================================================

program define maptile2
version 14.1
	
syntax varname(numeric) [if] [in], ///
	GEOgraphy(string asis) ///          geography time
	[geovar(varlist max=1) ///			geographic identifier var name
	savegraph(string) ///				save graph name
	NQuantiles(integer 10) ///          number of quantiles (bins)
	cutvalues(numlist ascending) ///    cut values (boundary pts) for bins
	ZOOMtoregion ///                    zoom in
	colorscheme(string) ///             color scheme from colorbrewer
	colors(string asis) ///             color list
	REVcolors invertcolors ///          reverse colors
	NOlegend ///                        do not display legend
	legdecimals(integer 2) ///          legend decimals
	legpercent ///                      legend entries as percentages
	formatstr(string asis) ///          legend format string
	LEGENDWidth(integer 0) ///          legend width
	LEGENDHeight(integer 0) ///         legend height
	labelmissing(string) ///       		legend missing data label
	legendstyle(string asis) ///        legend style
	nodisplay ///                       do not display PNG after running
	debug ///                           debug mode
	meshStates ///                      draw state boundaries
	meshCounties ///                    draw county boundaries
	makesvg ///                         make/open HTML for hi-res maps
	maurice ///                         high-resolution maps
	drawPrimaryRoads ///				primary roads (XX DELET EME)
	]

preserve
set more off


*-------------------------------------------------------------------------------
* Clean up arguments
*-------------------------------------------------------------------------------
	
* Set directory for the mapmaker python program
local map_dir "$dropbox/ado/mapmaker2/trunk"
if "`mapdirectory'"!="" {
	local map_dir "`mapdirectory'"`
}

* Store a local with the current working directory
local work_dir `c(pwd)'

* Mark variable specified to plot
local pvar `varlist'
	
* Mark geography variable, if specified
local gvar `geography'
if "`geovar'"!="" {
	rename `geovar' `geography'
}



* Just in case we run into permissions issues, use a random # in temp filename
local t = floor(20*runiform())+1

* If savegraph() not specified, saved as temp.png in working directory
if "`savegraph'"=="" {
	local savegraph "`work_dir'/temp.png"
}

* If savegraph() specified without folder, use current working directory
local x `savegraph'
if strpos("`savegraph'","\")==0 & strpos("`savegraph'","/")==0 {
	local savegraph "`work_dir'\\`x'"
}

* Deal with cutvalues
local len = 0 // could have used word count here, didn't work properly once
foreach x in `cutvalues' {
	local len = `len' + 1
}
local cuts
local curr = 1
foreach x in `cutvalues' {
	if `curr'<`len' {
		local cuts `cuts'`x',
	}
	else {
		local cuts `cuts'`x'
	}
	local curr = `curr' + 1
}
	
*-------------------------------------------------------------------------------
* Exception handling
*-------------------------------------------------------------------------------

* Prerequisite: Assert $dropbox points to valid directory
capture confirm $dropbox/newfile
if !_rc {
	di as red "You need to set up the global macro $dropbox to point to your synced Dropbox folder."
	exit 1
}
	
* Prequisite: Assert $dropbox/ado/ points to valid directory (/ado/ synced)
capture confirm $dropbox/ado/newfile
if !_rc {
	di as red "The /ado/ folder in Dropbox must be synced to use this script."
	exit 1
}

* XX no check to make sure output filename is valid

* colors, if specified, supercedes colorscheme
if "`colors'"!="" & "`colorscheme'"!="" {
	di as red "Warning: colors and colorscheme options both specified. colors takes precedent."
	local colorscheme ""
}

* XX colors should have same number of elements as bins if nonempty
if "`colors'"!="" {

}

* If colors() and colorscheme() empty, then choose colorscheme("RdYlGn") as default
if "`colors'"=="" & "`colorscheme'"=="" {
	local di_if_default "(default)"
	local colorscheme "RdYlGn"
}
	
* Make sure specified geography is valid
if "`geography'"!="cz" & "`geography'"!="county" & "`geography'"!="zip" & "`geography'"!="state" & "`geography'"!="tract2010_wa" & "`geography'"!="tract2010_um" & "`geography'"!="tract2010_lores" & "`geography'"!="puma2010" {
	di as red "Geography specified (`geography') not valid: can only do cz, county, zip, state, tract2010_wa, tract2010_um, or tract2010_lores."
	//exit 1
}
	
* legend format can't be specified with either legend percent or legend decimals
if "`legendformat'"!="" & (`legdecimals'!=2 | "`legpercent'"!="") {
	di as red "Cannot specify legend format string (`legendformat') with either legdecimals or legpercent."
	exit 1
}
	
* Nquantiles cannot be outside of range 2-10 inclusive
if `nquantiles'>10 | `nquantiles'<2 {
	di as red "Number of quantiles (`nquantiles') cannot be bigger than 10 or smaller than 2."
	exit 1
}
	
* Cannot specify both cutvalues and nquantiles
if `nquantiles'!=10 & "`cutvalues'"!="" {
	di as red "Cannot specify both cutvalues and nquantiles - choose one!"
	exit 1
}
	
* If legend is specified, must be one of four accepted types
if "`legendstyle'"!="" & "`legendstyle'"!="slice_slide" & "`legendstyle'"!="jama" & "`legendstyle'"!="basic" & "`legendstyle'"!="slice_under" {
	di as red "Legend style specified (`legendstyle') must be either slice_slide, jama, basic, or slice_under"
	exit 1
}

*-------------------------------------------------------------------------------
* Census tract-specific preparation
*-------------------------------------------------------------------------------

* If geovar() not specified, try to make it
if "`geovar'"=="" & ("`geography'"=="tract2010_um" | "`geography'"=="tract2010_wa" | "`geography'"=="tract2010_lores") {
	noi di "Census tract geographic identifier was not specified with geovar() option. Constructing a temporary geovar() to use instead."
	capture confirm numeric variable tract
	local rc1 = _rc
	capture confirm numeric variable county
	local rc2 = _rc
	capture confirm numeric variable state
	local rc3 = _rc
	if `rc1'==0 & `rc2'==0 & `rc3'==0 {
		gen temp_geoid = string(state,"%02.0f") + string(county,"%03.0f") + string(tract,"%06.0f")
		local defined_temp_geoid = 1
		local geovar temp_geoid
		rename `geovar' `geography'
	}
	else {
		noi di "Error: Couldn't find three numeric variables called tract, county, and state. Since no geovar() option was specified either, we need to exit."
		exit
	}
}
	
*-------------------------------------------------------------------------------
* Prepare data for mapping
*-------------------------------------------------------------------------------
	
* Restrict sample with if/in
marksample touse, strok novarlist
qui drop if `touse'==0
	
* Drop observations with missing geographic IDs
if "`gvar'"!="tract2010_wa" & "`gvar'"!="tract2010_um" & "`gvar'"!="tract2010_lores" {
	qui drop if `gvar'==.
}
if "`gvar'"=="tract2010_wa" | "`gvar'"=="tract2010_um" | "`gvar'"=="tract2010_lores" {
	qui drop if `gvar'==""
}

* Keep only geographic IDs and variable to plot
qui keep `pvar' `gvar'
qui order `gvar', first
		
* Navigate to maps directory
qui cd "`map_dir'"
	
* Export temporary dataset containing data to map
qui export delimited using "`map_dir'/temp/temp`t'.csv", replace

*-------------------------------------------------------------------------------
* Set up options for Python map maker
*-------------------------------------------------------------------------------

* Create baseline options macro
local opts -df temp/temp`t'.csv -gt `geography'
	
* number of quantiles
if `nquantiles'<10 & `nquantiles'>1  {
	local opts `opts' -pt `nquantiles'
}
	
* cut values
if "`cuts'"!="" {
	local xx "`cuts'"
	local opts `opts' -ct '`xx''
}
	
* color scheme
if "`colorscheme'"!="" {
	local opts `opts' -cs `colorscheme'
}

* color list
if "`colors'"!="" {
	local opts `opts' -cl `colors'
}
	
* reverse colors
if "`revcolors'"!="" | "`invertcolors'"!=""  {
	local opts `opts' -ic
}
	
* zoom to region
if "`zoomtoregion'"!=""  | ("`geography'"=="tract2010_wa" | "`geography'"=="tract2010_um" | "`geography'"=="tract2010_lores") {
	local opts `opts' -zr
}
	
* no legend
if "`nolegend'"!=""  {
	local opts `opts' -nl
}
	
* legend width
if `legendwidth'>0  {
	local opts `opts' -lw `legendwidth'
}
	
* legend height
if `legendheight'>0  {
	local opts `opts' -lh `legendheight'
}

* format legend decimals and percent, when format string not specified
if "`formatstr'"=="" {
	if "`legpercent'"=="" local opts `opts' -fs .`legdecimals'f
	if "`legpercent'"!="" local opts `opts' -fs .`legdecimals'%
}
	
* format legend, when format string specified
if "`formatstr'"!=""  {
	local opts `opts' -fs `"`formatstr'"'
}
	
* format string for missing labels
if "`labelmissing'"!=""  {
	local opts `opts' -lm "`""`labelmissing'""'"
}
	
* format legend style
if "`legendstyle'"!=""  {
	local opts `opts' -ls `legendstyle' 
}

* mesh states and mesh counties
if "`meshStates'"!=""  {
	local opts `opts' -ms 
}
if "`meshCounties'"!=""  {
	local opts `opts' -mc
}

if "`maurice'"!="" {
	local opts `opts' -hr
}

* Finally: add in -op
local opts `opts' -op "`savegraph'"
	
*di "Running map_maker.py with options: `opts'"
	
*-------------------------------------------------------------------------------
* Run Python map-maker script with options macro defined above
*-------------------------------------------------------------------------------

* If debug mode enabled, run Python script in a shell that won't disappear
if "`debug'"!="" {
	shell cmd /k python map_maker.py `opts'
}

* If debug not enabled, run python script in normal shell
if "`debug'"=="" {
	shell python map_maker.py `opts'
}

* if nodisplay isn't declared, load graph
if "`nodisplay'"=="" view browse `savegraph'
	
*-------------------------------------------------------------------------------
* Cleanup
*-------------------------------------------------------------------------------

* Go back to previous working directory
qui cd "`work_dir'"

* XX move this: if no geovar specified, then probably = geography?
if "`geovar'"=="" {
	local geovar "`geography'"
}

* Clean up temporary geovar for tract geos if defined
if "`defined_temp_geoid'"=="1" {
	cap drop temp_geovar
}

*-------------------------------------------------------------------------------
* Dislay output
*-------------------------------------------------------------------------------

di " "
di as text "{hline 80}"
di " Maptile2"
di " Variable mapped: `pvar'"
di " Geographic unit: `geography'"
di " Geographic identifier: `geovar'"
di " Output: `savegraph'"
di " Color scheme: `colorscheme' `di_if_default'"
di " Something wrong? Use the option 'debug' for more error information."
di " Check {help maptile2: help maptile2} for more usage details."
di as text "{hline 80}"

* Restore working dataset
restore
	
end
