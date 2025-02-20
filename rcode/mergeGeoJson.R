# This R script combines all the GeoJSON files in a folder into one file, then writes it back to the folder.
# Modified from its original source: https://gist.github.com/wildintellect/582bb1096092170070996d21037b82d8
# Version 2 rewritten to us sf which is way faster, comparison at the link above

library(sf)
library(dplyr)
#library(rgdal) - depreciated and no longer needed
library(lwgeom)
library(readr)
sf_use_s2(FALSE) # solves duplicated vertex error
#library(geojsonio)
#library(geojsonsf)

# probably want to change the pattern to exclude or filter after to drop the all.geojson file
# AVAs folder contains the completed AVA boundaries
# TBD folder contains the boundaries waiting to be completed - it will be empty once all of the AVAs are completed
avas <- list.files(path="./avas", pattern = "*json$", full.names = "TRUE")
tbd <- list.files(path="./tbd", pattern = "*json$", full.names = "TRUE")

#gj <- c(avas, tbd)
gj<- avas #we no longer need to include the TBD boundaries in the aggregated files. This line is awkward, but I want to keep the original structure in case we need it later. "gj" is short for geojson.

# exclude the all.geojson file... probably a more elegant way to do this, but this works:
gj <- gj[gj != "./avas.geojson"]
gj <- gj[gj != "./tbd/avas.geojson"]

# mark the start time so we can calculate how long it takes to run the process
c <- Sys.time()

# gread the geojson files
vectsf <- lapply(gj, read_sf)

#Bug, if date field has NA it's a char but valid dates are doubles, can't bind those
#Option convert after reading to char, or read as char to begin with
# converted the dates column as char 
vectsf2 <- lapply(vectsf, function(d){
  d$created <- as.Date(d$created, "%m/%d/%y")
  d$removed <- as.Date(d$removed, "%m/%d/%y")
  d$valid_start <- as.Date(d$valid_start, "%m/%d/%y")
  d$valid_end <- as.Date(d$valid_end, "%m/%d/%y")
  return(d)
  })

# put the polygons into one table
allsf <- do.call(rbind, vectsf2)

# replace N/A with NA
allsf <- mutate_if(allsf, is.character, gsub, pattern="N/A", replacement=NA) 

# replace blanks with NA in the valid_end column
allsf$valid_end[allsf$valid_end=='']<-NA

# ensure ava is valid
for (i in 1:nrow(allsf)) {
  
  # move on if the ava is valid
  if (st_is_valid(allsf[i,]) == TRUE) {
    next
    
  # if the ava is not valid, first set precision to 15 digits and then make the ava valid 
  } else {
    print(i)
    allsf[i,] <- st_set_precision(allsf[i,], 15)
    allsf[i,] <- st_make_valid(allsf[i,])
  }
}

# calculate the area of the polygons
#allsf$area <- st_area(allsf)

# arrange the polygons so the smaller ones are on top
allsf <- arrange(allsf,desc(st_area(allsf)))

#write_sf(allsf, dsn="avas.geojson", driver="GeoJSON", delete_dsn=TRUE)
#geojson_write(allsf, file="avas-sf.geojson", overwrite=TRUE, convert_wgs84 = TRUE)


# Separate the current & historic AVAs ---------------------------------
setwd("./avas_aggregated_files")

current.avas<-allsf[which(is.na(allsf$valid_end)),]
write_sf(current.avas, dsn="avas.geojson", driver="GeoJSON", delete_dsn=TRUE)

historic.avas<-allsf[which(nchar(allsf$valid_end)>0),]
write_sf(historic.avas, dsn="avas_historic.geojson", driver="GeoJSON", delete_dsn=TRUE)

write_sf(allsf, dsn="avas_allboundaries.geojson", driver="GeoJSON", delete_dsn=TRUE)

# Write JS file for Web Map-----------------------------------------------------------

#txt<-sf_geojson(current.avas) #this isn't writing the attribute table correctly
#text<-geojson_read("avas.geojson")
setwd('..') #move back to the ava folder
text<-readLines("./avas_aggregated_files/avas.geojson")
text<-paste(text, collapse = "")
js=paste0("var avas = ", text)
writeLines(js, "./docs/web_map/avas.js")


#how long did it take?
d <- Sys.time()
paste("This process finished in", d-c, "seconds.")
