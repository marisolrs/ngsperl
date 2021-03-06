options(bitmapType='cairo')

#load Rcpp package first because of the error with reshape2 package
library(Rcpp)

###############################################################################
# Functions in pipeline
###############################################################################
saveInError<-function(message="",filePrefix="",fileSuffix=paste0(Sys.Date(),".error")) {
	if (filePrefix=="") {
		filename<-fileSuffix
	} else {
		filename<-paste0(filePrefix,".",fileSuffix)
	}
	save.image(paste0(filename,".RData"))
	writeLines(message,paste0(filename))
	warning(message)
}

if(!exists("useLeastGroups")){
  useLeastGroups<-FALSE
}

getHeatmapOption<-function(countHT){
	labRow=""
	Rowv=NULL
	showRowDendro=FALSE
	cmargin=max(5, min(10,max(nchar(colnames(countHT)))/2))
	rmargin=5
	if(nrow(countHT) < 30){
		showRowDendro=TRUE
		labRow=NULL
		rmargin=min(10,max(nchar(row.names(countHT)))/2)
	}
	if(nrow(countHT) > 50000){
		Rowv=NA
	}
	margin=c(cmargin,rmargin)
	return(list(labRow=labRow, Rowv=Rowv, showRowDendro=showRowDendro, margin=margin))
}

theme_bw2 <- function () { 
	theme_bw() %+replace% 
		theme(
			panel.border = element_blank(),
			axis.line = element_line(colour = "black", size = 0.5)
		)
}

getSampleInGroup<-function(groupDefineFile, samples, comparisonDefineFile="", countTableTitle="", useLeastGroups=FALSE,onlySamplesInGroup=FALSE){
  groupData<-read.delim(groupDefineFile,as.is=T,header=F)
  if(comparisonDefineFile != ""){
    comparisonData<-read.delim(comparisonDefineFile,as.is=T,header=F)
    if(countTableTitle %in% comparisonData$V2){
      countTableGroups<-comparisonData[comparisonData$V2==countTableTitle,"V1"]
      groupData<-groupData[groupData$V2 %in% countTableGroups,]
    }
  }
  
  if(useLeastGroups){
    groupData<-groupData[which(groupData$V1 %in% samples),]
    groups<-lapply(unique(groupData$V2), function(x){
      nrow(groupData[groupData$V2==x,])
    })
    discardGroups<-NULL
    groupNames=unique(groupData$V2)
    for(i in c(1:length(groupNames))){
      sampleI<-groupData[groupData$V2==groupNames[i], "V1"]
      for(j in c(i+1:length(groupNames))){
        sampleJ<-groupData[groupData$V2==groupNames[j], "V1"]
        if(all(sampleI %in% sampleJ)){
          discardGroups<-c(discardGroups, groupNames[i])
          break
        }else if(all(sampleJ %in% sampleI)){
          discardGroups<-c(discardGroups, groupNames[j])
        }
      }
    }
    groupData<-groupData[!(groupData$V2 %in% discardGroups),]
  }
  groupData$V2<-factor(groupData$V2)
  
  res<-NULL
  gnameChanged<-FALSE
  for(sample in samples){
    stog<-groupData[groupData$V1==sample,,drop=F]
    if(nrow(stog) == 1){
      group<-stog[1,2]
    }else if(nrow(stog) > 1){
      groups<-stog$V2[order(stog$V2)]
      group<-paste(groups, collapse=":")
      gnameChanged<-TRUE
    }else{
      group<-"Unknown"
      gnameChanged<-TRUE
    }
    res<-rbind(res, data.frame(V1=sample, V2=group))
  }
  rownames(res)<-res$V1
  if(gnameChanged){
    sortedGroupNames<-sort(unique(res$V2))
    res$V2<-factor(res$V2, levels=sortedGroupNames)
  }
  
  if (onlySamplesInGroup) {
	  #remvoe "Unknown" group
	  res<-res[which(res$V2!="Unknown"),]
	  res$V2<-factor(as.character(res$V2))
  }
  
  return(res)
}

###############################################################################
# Functions for correlation calculation
###############################################################################

corTestVectorWithoutZero <- function(x, y, method="spearman") {
  #sumxy<-!is.na(x) & !is.na(y) & ((x != 0) | (y != 0))
  sumxy<-!is.na(x) & !is.na(y) & (x != 0) & (y != 0)
  ccx<-x[sumxy]
  ccy<-y[sumxy]
  cor.test(ccx, ccy, method=method)
}

corTestTableWithoutZero<-function(x, method ="spearman")
{
  if (is.data.frame(x))
    x <- as.matrix(x)
  if (!(is.numeric(x) || is.logical(x)))
    stop("'x' must be numeric")
  stopifnot(is.atomic(x))
  ncx <- ncol(x)
  if (ncx == 0)
    stop("'x' is empty")

  cnames<-colnames(x)
  result<-NULL
  for (i in c(1:(ncx-1))) {
    for (j in c((i+1):ncx)) {
      x2 <- x[, i]
      y2 <- x[, j]
      cc <- corTestVectorWithoutZero(x2, y2, method=method)
      result <- rbind(result, data.frame("Samples" = paste0(cnames[i], " ~ ", cnames[j]), "rho" = cc$estimate, "pvalue" = cc$p.value))
    }
  }
  return(result)
}

corVectorWithoutZero <- function(x, y, method="spearman") {
  #sumxy<-!is.na(x) & !is.na(y) & ((x != 0) | (y != 0))
  sumxy<-!is.na(x) & !is.na(y) & (x != 0) & (y != 0)
  ccx<-x[sumxy]
  ccy<-y[sumxy]
  cor(ccx, ccy, method=method)
}

corTableWithoutZero<-function(x, method ="spearman") 
{
  if (is.data.frame(x)) 
    x <- as.matrix(x)
  if (!(is.numeric(x) || is.logical(x))) 
    stop("'x' must be numeric")
  stopifnot(is.atomic(x))
  ncy <- ncx <- ncol(x)
  if (ncx == 0) 
    stop("'x' is empty")
  r <- matrix(0, nrow = ncx, ncol = ncy)
  for (i in seq_len(ncx)) {
    for (j in seq_len(i)) {
      x2 <- x[, i]
      y2 <- x[, j]
      r[i, j] <- corVectorWithoutZero(x2, y2, method=method)
    }
  }
  r <- r + t(r) - diag(diag(r))
  rownames(r) <- colnames(x)
  colnames(r) <- colnames(x)
  r
}


###############################################################################
# Functions in other visualization tasks
###############################################################################

myEstimateSizeFactors<-function(dds){
  library(DESeq2)
  sfres<-try(dds<-estimateSizeFactors(dds))
  if (class(sfres) == "try-error") {
    library(edgeR)
    y<-DGEList(counts=countNum)
    y<-calcNormFactors(y, methold="TMM")
    sizeFactors(dds)<-y$samples$norm.factors
  }
  return(dds)
}

library("VennDiagram")
venn.diagram1<-function (x, count=NULL,filename, height = 3000, width = 3000, resolution = 500, 
		units = "px", compression = "lzw", na = "stop", main = NULL, 
		sub = NULL, main.pos = c(0.5, 1.05), main.fontface = "plain", 
		main.fontfamily = "serif", main.col = "black", main.cex = 1, 
		main.just = c(0.5, 1), sub.pos = c(0.5, 1.05), sub.fontface = "plain", 
		sub.fontfamily = "serif", sub.col = "black", sub.cex = 1, 
		sub.just = c(0.5, 1), category.names = names(x), force.unique = TRUE,
		fill=NA,
		...) 
{
	if (is.null(count)) {
		countFun<-function(x) length(x)
	} else {
		countFun<-function(x) sum(count[x])
	}
	if (is.na(fill[1])) {
		if (length(x)==5) {
			fill = c("dodgerblue", "goldenrod1", "darkorange1", "seagreen3", "orchid3")
		} else if (length(x)==4) {
			fill = c("dodgerblue", "goldenrod1",  "seagreen3", "orchid3")
		} else if (length(x)==3) {
			fill = c("dodgerblue", "goldenrod1", "seagreen3")
		} else if (length(x)==2) {
			fill = c("dodgerblue", "goldenrod1")
		}
	}
	if (force.unique) {
		for (i in 1:length(x)) {
			x[[i]] <- unique(x[[i]])
		}
	}
	if ("none" == na) {
		x <- x
	}
	else if ("stop" == na) {
		for (i in 1:length(x)) {
			if (any(is.na(x[[i]]))) {
				stop("NAs in dataset", call. = FALSE)
			}
		}
	}
	else if ("remove" == na) {
		for (i in 1:length(x)) {
			x[[i]] <- x[[i]][!is.na(x[[i]])]
		}
	}
	else {
		stop("Invalid na option: valid options are \"none\", \"stop\", and \"remove\"")
	}
	if (0 == length(x) | length(x) > 5) {
		stop("Incorrect number of elements.", call. = FALSE)
	}
	if (1 == length(x)) {
		list.names <- category.names
		if (is.null(list.names)) {
			list.names <- ""
		}
		grob.list <- VennDiagram::draw.single.venn(area = countFun(x[[1]]), 
				category = list.names, ind = FALSE,fill=fill, ...)
	}
	else if (2 == length(x)) {
		grob.list <- VennDiagram::draw.pairwise.venn(area1 = countFun(x[[1]]), 
				area2 = countFun(x[[2]]), cross.area = countFun(intersect(x[[1]], 
								x[[2]])), category = category.names, ind = FALSE, 
				fill=fill,
				...)
	}
	else if (3 == length(x)) {
		A <- x[[1]]
		B <- x[[2]]
		C <- x[[3]]
		list.names <- category.names
		nab <- intersect(A, B)
		nbc <- intersect(B, C)
		nac <- intersect(A, C)
		nabc <- intersect(nab, C)
		grob.list <- VennDiagram::draw.triple.venn(area1 = countFun(A), 
				area2 = countFun(B), area3 = countFun(C), n12 = countFun(nab), 
				n23 = countFun(nbc), n13 = countFun(nac), n123 = countFun(nabc), 
				category = list.names, ind = FALSE, list.order = 1:3, 
				fill=fill,
				...)
	}
	else if (4 == length(x)) {
		A <- x[[1]]
		B <- x[[2]]
		C <- x[[3]]
		D <- x[[4]]
		list.names <- category.names
		n12 <- intersect(A, B)
		n13 <- intersect(A, C)
		n14 <- intersect(A, D)
		n23 <- intersect(B, C)
		n24 <- intersect(B, D)
		n34 <- intersect(C, D)
		n123 <- intersect(n12, C)
		n124 <- intersect(n12, D)
		n134 <- intersect(n13, D)
		n234 <- intersect(n23, D)
		n1234 <- intersect(n123, D)
		grob.list <- VennDiagram::draw.quad.venn(area1 = countFun(A), 
				area2 = countFun(B), area3 = countFun(C), area4 = countFun(D), 
				n12 = countFun(n12), n13 = countFun(n13), n14 = countFun(n14), 
				n23 = countFun(n23), n24 = countFun(n24), n34 = countFun(n34), 
				n123 = countFun(n123), n124 = countFun(n124), n134 = countFun(n134), 
				n234 = countFun(n234), n1234 = countFun(n1234), category = list.names, 
				ind = FALSE, fill=fill,...)
	}
	else if (5 == length(x)) {
		A <- x[[1]]
		B <- x[[2]]
		C <- x[[3]]
		D <- x[[4]]
		E <- x[[5]]
		list.names <- category.names
		n12 <- intersect(A, B)
		n13 <- intersect(A, C)
		n14 <- intersect(A, D)
		n15 <- intersect(A, E)
		n23 <- intersect(B, C)
		n24 <- intersect(B, D)
		n25 <- intersect(B, E)
		n34 <- intersect(C, D)
		n35 <- intersect(C, E)
		n45 <- intersect(D, E)
		n123 <- intersect(n12, C)
		n124 <- intersect(n12, D)
		n125 <- intersect(n12, E)
		n134 <- intersect(n13, D)
		n135 <- intersect(n13, E)
		n145 <- intersect(n14, E)
		n234 <- intersect(n23, D)
		n235 <- intersect(n23, E)
		n245 <- intersect(n24, E)
		n345 <- intersect(n34, E)
		n1234 <- intersect(n123, D)
		n1235 <- intersect(n123, E)
		n1245 <- intersect(n124, E)
		n1345 <- intersect(n134, E)
		n2345 <- intersect(n234, E)
		n12345 <- intersect(n1234, E)
		grob.list <- VennDiagram::draw.quintuple.venn(area1 = countFun(A), 
				area2 = countFun(B), area3 = countFun(C), area4 = countFun(D), 
				area5 = countFun(E), n12 = countFun(n12), n13 = countFun(n13), 
				n14 = countFun(n14), n15 = countFun(n15), n23 = countFun(n23), 
				n24 = countFun(n24), n25 = countFun(n25), n34 = countFun(n34), 
				n35 = countFun(n35), n45 = countFun(n45), n123 = countFun(n123), 
				n124 = countFun(n124), n125 = countFun(n125), n134 = countFun(n134), 
				n135 = countFun(n135), n145 = countFun(n145), n234 = countFun(n234), 
				n235 = countFun(n235), n245 = countFun(n245), n345 = countFun(n345), 
				n1234 = countFun(n1234), n1235 = countFun(n1235), n1245 = countFun(n1245), 
				n1345 = countFun(n1345), n2345 = countFun(n2345), n12345 = countFun(n12345), 
				category = list.names, ind = FALSE,fill=fill, ...)
	}
	else {
		stop("Invalid size of input object")
	}
	if (!is.null(sub)) {
		grob.list <- add.title(gList = grob.list, x = sub, pos = sub.pos, 
				fontface = sub.fontface, fontfamily = sub.fontfamily, 
				col = sub.col, cex = sub.cex)
	}
	if (!is.null(main)) {
		grob.list <- add.title(gList = grob.list, x = main, pos = main.pos, 
				fontface = main.fontface, fontfamily = main.fontfamily, 
				col = main.col, cex = main.cex)
	}
	grid.newpage()
	grid.draw(grob.list)
	return(1)
#	return(grob.list)
}


###############################################################################
# Funtions in count table barplot and pie chart
###############################################################################
library(reshape2)
library(ggplot2)
library(RColorBrewer)
library(scales)

getFacetColCount<-function(groupFileList){
	result=0
	if(groupFileList != ''){
		sampleToGroup=read.delim(groupFileList,as.is=T,header=F)
		groupCount=unique(table(sampleToGroup$V2))
		if(length(groupCount) == 1){
			result=groupCount
		}
	}
	return(result)
}

orderDataByNames<-function(x,orderKey,orderNames) {
	orderedInd<-NULL
	for (i in orderNames) {
		orderedInd<-c(orderedInd,which(orderKey==i))
	}
	return(x[orderedInd,])
}

#Merge Sample By Group
#comment it as the same function (improved) is in the end
#mergeTableBySampleGroup<-function(x,sampleToGroup,toPercent=TRUE) {
#  if (toPercent) {
#    xRatio<-t(t(x)/colSums(x,na.rm=T))
#  } else {
#    xRatio<-x
#  }
#  groupLength<-length(unique(sampleToGroup[,2]))
#  xRatioGroupMean<-matrix(NA,ncol=groupLength,nrow=nrow(x))
#  
#  #keep the order of group by the levels of sampleToGroup$V2
#  colnames(xRatioGroupMean)<-as.character(sort(unique(sampleToGroup[,2])))
#  
#  row.names(xRatioGroupMean)<-row.names(x)
#  for (i in 1:groupLength) {
#    currentSample<-sampleToGroup[which(sampleToGroup[,2]==colnames(xRatioGroupMean)[i]),1]
#    xRatioGroupMean[,i]<-rowMeans(xRatio[,currentSample,drop=FALSE],na.rm=T)
#  }
#  return(xRatioGroupMean)
#}

#extract part of color from a color range
col_part<-function(data_all,data_part,col) {
	min_all<-min(data_all,na.rm=T)
	max_all<-max(data_all,na.rm=T)
	min_part<-min(data_part,na.rm=T)
	max_part<-max(data_part,na.rm=T)
	if (min_part<min_all) {
		min_part<-min_all
		warning(paste0("Minimum value in data_part is less than data_all"))
	}
	if (max_part>max_all) {
		max_part<-max_all
		warning(paste0("Maximum value in data_part is larger than data_all"))
	}
	cut_off_low<-round(quantile(1:length(col),(min_part-min_all)/(max_all-min_all)))
	cut_off_high<-round(quantile(1:length(col),(max_part-min_all)/(max_all-min_all)))
	col=col[cut_off_low:cut_off_high]
	return(col)
}

basicPie<-function(x,maxCategory=10,main="",addPercent=F) {
	nameToCountForFigure<-na.omit(rev(sort(x)))
	if (length(nameToCountForFigure)>maxCategory) {
		nameToCountForFigure<-c(nameToCountForFigure[1:(maxCategory-1)],Other=sum(nameToCountForFigure[-(1:(maxCategory-1))]))
	}
	if (addPercent) {
		temp<-round(nameToCountForFigure/sum(nameToCountForFigure)*100,0)
		names(nameToCountForFigure)<-paste0(names(nameToCountForFigure)," ",temp,"%")
	}
	pie(nameToCountForFigure,col=rainbow(length(nameToCountForFigure)),main=main)
}

makeColors<-function(n,colorNames="Set1") {
	maxN<-brewer.pal.info[colorNames,"maxcolors"]
	if (n<=maxN) {
		colors<-brewer.pal(n, colorNames)
	} else {
		colors<-colorRampPalette(brewer.pal(maxN, colorNames))(n)
	}
	return(colors)
}

tableMaxCategory<-function(dat,maxCategory=NA) {
	if (!is.na(maxCategory) & nrow(dat)>maxCategory) {
		temp<-apply(dat,2,function(x) rev(order(x))[1:maxCategory])
		categoryKeptInd<-sort(unique(as.vector(temp)))
		datForFigure<-dat[categoryKeptInd,]
		if (length(categoryKeptInd)<nrow(dat)) {
			datForFigure<-rbind(datForFigure,Other=colSums(dat[-categoryKeptInd,,drop=FALSE]))
		}
	} else {
		datForFigure<-dat
	}
	return(datForFigure)
}

tableBarplot<-function(dat,maxCategory=5,x="Sample", y="Reads",fill="Category",facet=NA,varName=if (is.na(facet)) c(fill,x,y) else c(facet,x,y),transformTable=TRUE,textSize=20,ylab=y,colorNames="Set1",barwidth=0.5) {
	if (transformTable) {
		datForFigure<-tableMaxCategory(dat,maxCategory=maxCategory)
		
#		datForFigure$Groups<-row.names(dat)
		datForFigure<-melt(as.matrix(datForFigure))
		colnames(datForFigure)<-varName
	} else {
		datForFigure<-dat
	}
	if (!is.na(fill)) {
		p<-ggplot(datForFigure,aes_string(x=x,y=y,fill=fill))
		if (length(unique(datForFigure[,fill]))<=7 & sum(nchar(as.character(unique(datForFigure[,fill]))))<70) {
			p<-p+theme(legend.position = "top")+
					guides(fill = guide_legend(nrow = 1,keywidth = 2, keyheight = 2))
		} else {
			p<-p+	guides(fill = guide_legend(ncol = 1,keywidth = 1, keyheight = 1))
		}
		if (colorNames!="") {
			colors<-makeColors(length(unique(datForFigure[,fill])),colorNames)
			p<-p+scale_fill_manual(values=colors)
		}
	} else if (!is.na(facet)) {
		p<-ggplot(datForFigure,aes_string(x=x,y=y))+facet_wrap(c(facet))
	} else {
		p<-ggplot(datForFigure,aes_string(x=x,y=y))
	}
	p<-p+geom_bar(stat="identity", width=barwidth)+
#			guides(fill= guide_legend(title = groupName))+
			theme(axis.text.x=element_text(angle=90,hjust=1,vjust=0.5)) + 
			theme(axis.text = element_text(size=textSize),legend.text=element_text(size=textSize),
					axis.title = element_text(size=textSize),legend.title= element_text(size=textSize))+
			ylab(ylab)

	return(p)
}

tableBarplotToFile<-function(dat,fileName,totalCountFile="",groupFileList="",outFileName="",maxCategory=5,textSize=9,transformTable=T,height=1500,proportionBar=TRUE,...) {
	if (totalCountFile!="") { #normlize with total count *10^6
		totalCount<-read.csv(totalCountFile,header=T,as.is=T,row.names=1,check.names=FALSE)
		totalCount<-unlist(totalCount["Reads for Mapping",])
		dat<-10^6*t(t(dat)/totalCount[colnames(dat)])
		ylab<-"Mapped Reads per Million"
	} else {
		ylab<-"Reads"
	}
	if (groupFileList!="") {
		sampleToGroup<-read.delim(groupFileList,as.is=T,header=F)
		#keep the groups with samples in the count table
		sampleToGroup<-sampleToGroup[which(sampleToGroup[,1] %in% colnames(dat)),]
		dat<-mergeTableBySampleGroup(dat,sampleToGroup,toPercent=FALSE)
		if (outFileName!="") {
			write.csv(dat,outFileName)
		}
	}
	width<-max(3000,75*ncol(dat))
	height<-height
	png(fileName,width=width,height=height,res=300)
	p<-tableBarplot(dat,maxCategory=maxCategory,textSize=textSize,ylab=ylab,transformTable=transformTable,...)
	print(p)
	dev.off()
	if (proportionBar) {
		fileNameProportion<-gsub(".png$",".Proportion.png",fileName)
		png(fileNameProportion,width=width,height=height,res=300)
		p$layers <- c(geom_bar(stat="identity",position="fill"))
		print(p+scale_y_continuous(labels = percent_format())+ylab("Proportion"))
		dev.off()
	}
}

readLayout <-function(visLayoutFileList, visLayoutAlphabet=FALSE){
  visLayout<-read.delim(visLayoutFileList,as.is=T,header=F)
  visLayout<-sapply(split(visLayout[,1],visLayout[,2]),function(x) x)
  row.names(visLayout)<-visLayout[,"Groups"]
  visLayout<-data.frame(visLayout[,-which(colnames(visLayout)=="Groups")])
  if(!visLayoutAlphabet){
    visLayout$Col_Group<-factor(visLayout$Col_Group,levels=unique(visLayout$Col_Group))
    visLayout$Row_Group<-factor(visLayout$Row_Group,levels=unique(visLayout$Row_Group))
  }
  return(visLayout)
}
    
getLayoutWidth<-function(visLayout, minWidth=2000, cellWidth=800){
  rowLength<-length(unique(visLayout[which(visLayout[,2]=="Row_Group"),1]))
  colLength<-length(unique(visLayout[which(visLayout[,2]=="Col_Group"),1]))
  maxLength=max(rowLength, colLength)
  result<-max(minWidth,maxLength*cellWidth)
  return(result)
}
    
#changed from function in http://mathematicalcoffee.blogspot.com/2014/06/ggpie-pie-graphs-in-ggplot2.html
ggpie <- function (dat, fill="Category", y="Reads",facet="Sample", 
		maxCategory=NA,main=NA, percent=T,textSize=15,colorNames="Set1",
		transformTable=TRUE,reOrder=FALSE,visLayoutFileList="",visLayoutAlphabet=FALSE,facetColCount=0) {
	if (transformTable) {
		datForFigure<-tableMaxCategory(dat,maxCategory=maxCategory)
		
	    if (percent) {
		    datForFigure<-t(t(datForFigure)/colSums(datForFigure,na.rm=T))
	    }
		if (reOrder) {
			if (row.names(datForFigure)[nrow(datForFigure)]=="Other") {
				categoryOrderedNames<-c(row.names(datForFigure)[-nrow(datForFigure)][rev(order(rowSums(datForFigure[-nrow(datForFigure),])))],"Other")
			} else {
				categoryOrderedNames<-row.names(datForFigure)[rev(order(rowSums(datForFigure)))]
			}
		} else {
			categoryOrderedNames<-row.names(datForFigure)
		}
		datForFigure<-melt(as.matrix(datForFigure),as.is=T)
		colnames(datForFigure)<-c(fill,facet,y)
	} else {
		datForFigure<-dat
		if (percent) {
			if (!is.na(facet)) {
				temp<-tapply(datForFigure[,y],datForFigure[,facet],sum)
				datForFigure[,y]<-datForFigure[,y]/temp[datForFigure[,facet]]
			} else {
				datForFigure[,y]<-datForFigure[,y]/sum(datForFigure[,y])
			}
		}
		if (reOrder) {
			categoryOrderedNames<-unique(datForFigure[,fill])[rev(order(tapply(datForFigure[,y],datForFigure[,fill],sum)))]
		} else {
			categoryOrderedNames<-unique(datForFigure[,fill])
		}
	}
	datForFigure[,fill]<-factor(datForFigure[,fill],levels=categoryOrderedNames)
	datForFigure<-orderDataByNames(datForFigure,datForFigure[,fill],categoryOrderedNames)
	
	if (visLayoutFileList!="") {
		visLayout<-readLayout(visLayoutFileList, visLayoutAlphabet)
		datForFigure<-data.frame(datForFigure,visLayout[datForFigure[,2],])
	}
	
	p = ggplot(datForFigure, aes_string(x=factor(1), y=y, fill=fill)) +
			geom_bar(width=1, stat='identity', color='black') +
			guides(fill=guide_legend(keywidth = 1.5, keyheight = 1.5,override.aes=list(colour=NA))) + # removes black borders from legend
			coord_polar(theta='y') +
			theme(axis.ticks=element_blank(),
					axis.text.y=element_blank(),
					axis.text.x=element_blank(),
					axis.title=element_blank(),
					panel.grid=element_blank()) +
			#scale_y_continuous(breaks=cumsum(datForFigure[[y]])-datForFigure[[y]]/2, labels=datForFigure[[fill]]) +
			theme(panel.background = element_rect(fill = "white"))+
			theme(legend.text=element_text(size=textSize),
					legend.title= element_text(size=textSize),
					strip.text.x = element_text(size = textSize),
					strip.text.y = element_text(size = textSize))
	if (!is.na(main)) {
		p = p + ggtitle(main)
	}
	if (visLayoutFileList!="") {
		p<-p+facet_grid(Row_Group~Col_Group)
		if (length(unique(datForFigure$Row_Group))<length(unique(datForFigure$Col_Group))) {
			p<-p+theme(legend.position="top")
			if (max(nchar(as.character(datForFigure[,fill])))>20) {
				p<-p+guides(fill= guide_legend(ncol = 2))
			}
		}
	} else if (!is.na(facet)) {
		if(facetColCount > 0){
			p<-p+facet_wrap(c(facet), ncol=facetColCount)
		}else{
			p<-p+facet_wrap(c(facet))
		}
#		p<-p+facet_wrap(c(facet),nrow=2)+theme(legend.position="top")
	}

	if (!is.na(colorNames)) {
		colors<-makeColors(length(unique(datForFigure[,fill])),colorNames)
		p<-p+scale_fill_manual(values=colors)
	}
	return(p)
}

ggpieToFile<-function(dat,fileName,fill="Category", maxCategory=5,textSize=9,transformTable=TRUE,visLayoutFileList="",visLayoutAlphabet=FALSE,facetColCount=0,perHeight=700,...) {
	if (visLayoutFileList!="") {
		visLayout<-read.delim(visLayoutFileList,as.is=T,header=F)
		rowLength<-length(unique(visLayout[which(visLayout[,2]=="Row_Group"),1]))
		colLength<-length(unique(visLayout[which(visLayout[,2]=="Col_Group"),1]))
		maxLength=max(rowLength, colLength)
		height<-max(2000,maxLength*perHeight)
	} else {
		if (transformTable) {
			height<-max(2000,(as.integer(sqrt(ncol(dat)))+1)*perHeight)
		} else {
      height<-max(2000,(as.integer(sqrt(nrow(dat)))+1)*perHeight)
		}
	}
	width<-height
	
	png(fileName,width=width,height=height,res=300)
	p<-ggpie(dat,fill=fill, maxCategory=maxCategory,textSize=textSize,transformTable=transformTable,visLayoutFileList=visLayoutFileList,visLayoutAlphabet=visLayoutAlphabet,facetColCount=facetColCount,...)
	print(p)
	dev.off()
	invisible(p)
}

ggpieGroupToFile<-function(dat,fileName,groupFileList="",outFileName="",
		maxCategory=5,textSize=9,transformTable=TRUE,fill="Category", 
		y="Reads",facet="Sample",visLayoutFileList="",visLayoutAlphabet=FALSE,...) {
	if (groupFileList!="") {
		if (!transformTable) {
			if (is.factor(dat[,fill])) {
				fillOrder<-levels(dat[,fill])
			} else {
				fillOrder<-unique(dat[,fill])
			}
			dat<-acast(dat,as.formula(paste(fill,"~",facet)),value.var=y)
			dat<-dat[fillOrder,]
		}
		
		sampleToGroup<-read.delim(groupFileList,as.is=T,header=F)
		#keep the groups with samples in the count table
		sampleToGroup<-sampleToGroup[which(sampleToGroup[,1] %in% colnames(dat)),]
		
		datBySampleGroup<-mergeTableBySampleGroup(dat,sampleToGroup)
		if (outFileName!="") {
			write.csv(datBySampleGroup,outFileName)
		}
		p<-ggpieToFile(datBySampleGroup,fileName=fileName,maxCategory=maxCategory,textSize=textSize,
				transformTable=TRUE,fill=fill,y=y,facet=facet,visLayoutFileList=visLayoutFileList,visLayoutAlphabet=visLayoutAlphabet,facetColCount=0,...)
		invisible(p)
	}
}

expandCountTableByName<-function(x,sep=";") {
	namesEach<-strsplit(row.names(x),sep)
	namesEachUnlist<-unlist(namesEach)
	namesEachLength<-sapply(namesEach,length)
	xEach<-x/namesEachLength
	result<-xEach[rep(seq.int(1,nrow(xEach)), namesEachLength),]
	row.names(result)<-namesEachUnlist
	return(result)
}

aggregateCountTable<-function(x,group,method=sum) {
	result<-aggregate(x, list(factor(group,levels=unique(group))), method)
	row.names(result)<-result[,1]
	result<-result[,-1]
	return(result)
}

shortSpeciesName<-function(x) {
	res<-sapply(strsplit(x," |_"),function(x) {
	  if (length(x)<=3) {
      paste(x,collapse=" ")
    } else if (grepl("^\\d+$",x[2]) | x[2]=="ATCC") {
      paste(x[1:3],collapse=" ")
    } else {
      paste(x[1:2],collapse=" ")
    }
	})
  if(length(unique(res)) != length(res)){
    return(x)
  }else{
    return(res)
  }
}

countTableToSpecies<-function(dat,databaseLogFile="",outFileName="",shortName=T) {
	if (databaseLogFile!="") { #Species Count Table
		databaseLog<-read.delim(databaseLogFile,header=T,as.is=T)
		id2Species<-databaseLog$Species
		names(id2Species)<-databaseLog$Id
		
		mappingResultExpand<-expandCountTableByName(dat)
		speciesInMappingResult<-id2Species[row.names(mappingResultExpand)]
		
		mappingResult2Species<-aggregateCountTable(mappingResultExpand,speciesInMappingResult)
		
		#short name
		if (shortName) {
			row.names(mappingResult2Species)<-shortSpeciesName(row.names(mappingResult2Species))
		}
		if (outFileName!="") {
			write.csv(mappingResult2Species,outFileName)
		}
	} else {
		mappingResult2Species<-dat
		if (shortName) {
			row.names(mappingResult2Species)<-shortSpeciesName(row.names(mappingResult2Species))
		}
	}
	return(mappingResult2Species)
}

##########################
#functions added 20170429 for count table correlation
##########################
rowMedians<-function(x,...) {
	result<-apply(x,1,median,...)
	return(result)
}
mergeTableBySampleGroup<-function(x,sampleToGroup,toPercent=TRUE,rowFun=rowMeans,groupMinMedian=NULL) {
	if (toPercent) {
		xRatio<-t(t(x)/colSums(x,na.rm=T))
	} else {
		xRatio<-x
	}
	groupLength<-length(unique(sampleToGroup[,2]))
	xRatioGroupMean<-matrix(NA,ncol=groupLength,nrow=nrow(x))
	
	#keep the order of group by the levels of sampleToGroup$V2
	colnames(xRatioGroupMean)<-as.character(sort(unique(sampleToGroup[,2])))
	
	row.names(xRatioGroupMean)<-row.names(x)
	for (i in 1:groupLength) {
		currentSample<-as.character(sampleToGroup[which(sampleToGroup[,2]==colnames(xRatioGroupMean)[i]),1])
#		xRatioGroupMean[,i]<-rowMeans(xRatio[,currentSample,drop=FALSE],na.rm=T)
		xRatioGroupMean[,i]<-rowFun(xRatio[,currentSample,drop=FALSE],na.rm=T)
		if (!is.null(groupMinMedian)) {
			temp<-apply(xRatio[,currentSample,drop=FALSE],1,median,na.rm=T)
			removeInd<-which(temp<groupMinMedian)
			if (length(removeInd)>0) {
				xRatioGroupMean[removeInd,i]<-NA
			}
		}
	}
	return(xRatioGroupMean)
}
filterCountTable<-function(countNum,groupFileList="",minMedian=1,minMedianInGroup=1) {
	minMedianInd<-apply(countNum,1,median)
	if (any(minMedianInd<minMedian)) {
		countNum<-countNum[-which(minMedianInd<minMedian),]
		print(paste0(length(which(minMedianInd<minMedian))," reads/genes were removed due to median less than ",minMedian))
	}
	if (groupFileList!="") {
		sampleToGroup<-getSampleInGroup(groupFileList, colnames(countNum), comparisonFileList, countTableTitle, useLeastGroups)
		countNumGroup<-mergeTableBySampleGroup(countNum,sampleToGroup,toPercent=FALSE,rowFun=rowMedians)
		minGroupMedianInd<-apply(countNumGroup,1,min)
		if (all(minGroupMedianInd<minMedianInGroup)) {
			countNum<-countNum[-which(minGroupMedianInd<minMedianInGroup),]
			print(paste0(length(which(minGroupMedianInd<minMedianInGroup))," reads/genes were removed due to minimal group median less than ",minMedianInGroup))
		}
	}
	return(countNum)
}


###############################################################################
# End funtions in count table barplot and pie chart
# Start defining parameters for functions
###############################################################################

if (!exists("maxCategory")) {
	maxCategory=5
}
if (!exists("textSize")) {
	textSize=9
}
if (!exists("groupTextSize")) {
	groupTextSize=10
}

###############################################################################
# End defining parameters for functions
###############################################################################
