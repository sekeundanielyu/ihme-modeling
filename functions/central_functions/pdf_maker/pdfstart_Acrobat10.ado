/*
Author: Kyle Foreman (kfor@uw.edu)
	Institute for Health Metrics and Evaluation (http://www.healthmetricsandevaluation.org/)
Description: first program to call when creating a multi-page pdf; 
	defines globals and begins making the .ps and .do files needed later
Date: October 29, 2010
Version: 1.2
*/

capture program drop pdfstart
program define pdfstart
syntax using/ [, distexe(string)]
	// the program will be called by typing -pdfstart using pdffile.pdf[, distexe(acrodist.exe location)]-

local pdfarg = "`using'"
local pdfarg = trim("`pdfarg'")
	// get rid of any unnecessary blanks in the name
local pdfarg = subinstr("`pdfarg'","\","/",.)
	// change all the slashes to forward slashes

if c(os) == "Unix" {
	local pdfarg = subinstr("`pdfarg'","J:/","/home/j/",.)
		// make sure the path is correct if using Linux
}

tokenize `pdfarg', parse(/)
	// break the path down into pieces
local token_num = 1
local stop = 0
local pdfdir
while `stop' == 0 {
	if match("``token_num''","*.pdf") == 1 {
		local pdfname "``token_num''"
		local stop = 1
	}
	else {
		local pdfdir `pdfdir'``token_num''
		capture mkdir "`pdfdir'"
		local token_num = `token_num' + 1
		if `token_num' == 100 {
			display in red "You must include [pdfname].pdf following the -pdfstart- command"
			error 197
		}
	}
}
	// this stuff just makes two separate locals - one contains the file path, the other the name of the pdf file

global pdfname = regexr("`pdfname'",".pdf","")
global pdfdir "`pdfdir'"
	// save the arguments as globals, as subsequent programs will need them

if c(os) == "Windows" {
	if "`distexe'" == "" {
		global acrodist "C:/Program Files/Adobe/Acrobat 10.0/Acrobat/acrodist.exe"
		capture confirm file "$acrodist"
		if !_rc != 1 {
			global acrodist "C:/Program Files (x86)/Adobe/Acrobat 10.0/Acrobat/acrodist.exe"
		}
		di in green "Using default Distiller location: $acrodist"
	}
	else {
		global acrodist "`distexe'"
		di in green "Using user-specified Distiller location: $acrodist"
	}
	capture confirm file "$acrodist"
	if !_rc != 1 {
		di in red "Acrobat Distiller could not be found in the specified location:" _n "$acrodist" _n `"Specify the location of acrodist.exe using the syntax -pdfstart "[pdfdir]/[pdffile].pdf" "[distiller path]/acrodist.exe"-"'
		error 601
	}
		// if no third parameter is specified, then the default Acrobat 9.0 Windows distiller is assumed
		// if a different executable is defined, then switches to that
}
else if c(os) == "Unix" {
	global acrodist "/usr/bin/ghostscript"
		// use the default ghostscript directory if using Linux
}

if "`pdfdir'" == "" {
	global pdfdir = subinstr("`c(pwd)'","\","/",.)
	display in green "You have not specified a directory, so your pdf will be saved in the working directory:" _n "$pdfdir$pdfname.pdf"
}
else {
	display in green "PDF will be saved in:" _n "$pdfdir$pdfname.pdf"
}
	// let the user know where the pdf is being saved to

capture mkdir "$pdfdir/$pdfname"
	// make a temporary directory for all these files to be placed into


qui file open do_file using "$pdfdir/$pdfname.do", write replace text
if c(os) == "Windows" {
	file write do_file `"di in green "Removing tmp files""' _n
	file write do_file `"erase "$pdfdir$pdfname.ps""' _n
}
else if c(os) == "Unix" {
	file write do_file `"di in green "Removing tmp files""' _n
}
file close do_file
	// start the do-files that will be used to clean up all the tmp files at the end of the program

graph set ps tmargin .25
graph set ps lmargin 0
graph set ps logo off
graph set ps mag 200
graph set ps orientation landscape
graph set ps pagesize letter
set scheme s1color
	// setup all the postscript graphing options we want

if c(os) == "Windows" {
	qui file open ps_file using "$pdfdir/$pdfname.ps", write replace text
	file write ps_file `"/prun { /mysave save def"' _n
	file write ps_file `"	dup = flush"' _n
	file write ps_file `"	RunFile"' _n
	file write ps_file `"	clear cleardictstack"' _n
	file write ps_file `"	mysave restore"' _n
	file write ps_file `"} def"' _n
	file close ps_file
}
	// these steps create the first portion of the .ps file that distiller will eventually use to create the final pdf in Windows

else if c(os) == "Unix" {
	global pdfdir_nospace = subinstr("$pdfdir"," ","\ ",.)
	global pdfname_nospace = subinstr("$pdfname"," ","\ ",.)
	global gs_cmd "$acrodist -dBATCH -dSAFER -DNOPAUSE -q -sDEVICE=pdfwrite -sOutputFile=$pdfdir_nospace/$pdfname_nospace.pdf -f"
}
	// if using Linux, then start a global which will contain all the command line parameters we need to run later

global current_graph 1
	// this is a counter for knowing which graph we're on in the later program

end
