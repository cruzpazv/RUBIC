% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/load.data.R
\name{read.markers}
\alias{read.markers}
\title{Read the markers file in TSV format.}
\usage{
read.markers(markers.file, header = T)
}
\arguments{
\item{markers.file}{The name of the file containig the markers.}

\item{header}{A boolean value that specifies whether the file contain a header line.}
}
\value{
A \code{data.table} containing the markers.
}
\description{
Read the markers file in TSV format.
}
