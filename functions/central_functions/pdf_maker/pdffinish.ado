/*
Author: Kyle Foreman (kfor@uw.edu)
	Institute for Health Metrics and Evaluation (http://www.healthmetricsandevaluation.org/)
Description: third and final program to call when creating multi-page pdfs;
	uses Distiller to combine all the files into a single PDF, then erases the .ps files
Date: October 29, 2010
Version: 1.2
*/

capture program drop pdffinish
program define pdffinish
	// the program will be called by typing -pdffinish-
	// it will continue using the pdfname defined in the previous -pdfstart- command

syntax [, view]
	// if the option -view- is specified after -pdffinish- then Acrobat will open the finished file upon completion

if "$pdfname" == "" {
	display in red "Error: You must first run -pdfstart- and define the pdf name and directory"
	error 197
}
	// make sure that pdfstart was run first

if c(os) == "Windows" {
	if "`view'" == "view" {
		! "$acrodist" /F /N /V /Q "$pdfdir/$pdfname.ps"
			// run Distiller to create the pdf file, with viewing enabled
	}
	else {
		! "$acrodist" /F /N /Q "$pdfdir/$pdfname.ps"
			// run Distiller but without opening the completed file afterwards
	}
}
else if c(os) == "Unix" {
	! $gs_cmd
}

quietly do "$pdfdir/$pdfname.do"
	// erase all the temporary .ps files created along the way

erase "$pdfdir/$pdfname.do"
	// finally, erase the temporary .do file

capture rmdir "$pdfdir/$pdfname"
	// get rid of the entire temporary directory

end
