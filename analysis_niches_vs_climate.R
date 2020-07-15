library(ggplot2)
library(fUnitRoots) 
library(parallel)
library(foreach)
library(iterators)
library(doParallel)
library(xtable)
library(cowplot)

ss <- TRUE

# Data prep ---------------------------------------------------------------
day <- format(as.Date(date(), format="%a %b %d %H:%M:%S %Y"), format='%y-%m-%d')

# foram data
spAttr <- read.csv('Data/foram_spp_data_20-04-05.csv', stringsAsFactors=FALSE)
if (ss){
  df <- read.csv('Data/foram_niche_sumry_metrics_0m_20-04-05.csv', stringsAsFactors=FALSE)
} else {
  df <- read.csv('Data/foram_niche_sumry_metrics_20-04-05.csv', stringsAsFactors=FALSE)
}
ordr <- order(df$bin, decreasing = TRUE)
df <- df[ordr,]
bins <- unique(df$bin)
nbin <- length(bins)
spp <- unique(df$sp)
nspp <- length(spp)
binL <- bins[1] - bins[2]

# standardized sampling universe (MAT at range-through core sites) at each of 4 depths
truncEnv <- readRDS('Data/sampled_temp_ym_truncated_by_depth_20-04-05.rds')
envNm <- 'temp_ym'

# mean MAT over the globe, at a standard grid of lat-long points
glob <- read.csv('Data/global_surface_MAT_at_grid_pts_4ka.csv')
cols <- paste0('X',bins)
globMean <- colMeans(glob[,cols])

# Scatterplot -------------------------------------------------------------

# Mean species H overlap vs delta sampled (surface) MAT in each bin.
# H does not indicate direction, only magnitude of niche overlap,
# so should compare it with absolute differences in available MAT.

sumH <- function(b){
  bBool <- df$bin==b
  slc <- df[bBool,]
  lwrB <- quantile(slc$h, 0.25, na.rm = TRUE)
  uprB <- quantile(slc$h, 0.75, na.rm = TRUE)
  avgB <- mean(slc$h, na.rm=TRUE)
  binN <- nrow(slc)
  c(bin=b, lwr=lwrB, upr=uprB, h=avgB, nSpp=binN)
}
bybin <- sapply(bins, sumH)
bybin <- data.frame(t(bybin))

# mean MAT at all sampled sites in each bin:
sampAvg <- vector(length = nbin)
samp <- truncEnv$temp_ym_0m$samp
for (i in 1:nbin){
  bBool <- samp$bin==bins[i]
  sampAvg[i] <- mean(samp$temp_ym[bBool])
}
# cor(globMean, sampAvg)

# all H values are NA at most recent time step
Hseq <- bybin[-nrow(bybin),]

# delta MAT time series is stationary but H series is NOT
delta <- diff(sampAvg) # diff(globMean)
absDelta <- abs(delta)
Hseq$absDelta <- absDelta
adfTest(absDelta) 
acf(absDelta) 
adfTest(Hseq$h)
plot(acf(Hseq$h), ci.type="ma")
# account for non-stationarity and autocorrelation
arH <- arima(Hseq$h, order=c(1,0,0))
resid <- as.numeric(arH$residuals)
adfTest(resid)
acf(resid)
arH$coef
lmH <- lm(resid ~ absDelta) 
acf(lmH$residuals)
cor.test(resid, absDelta, method='pear')

xmx <- max(Hseq$absDelta) * 1.1
deltaPlot <- 
  ggplot(data=Hseq, aes(x=absDelta, y=h)) +
  theme_bw() +
  scale_y_continuous('Intraspecific niche H distance', 
                     limits=c(0, 0.52), expand=c(0, 0)) +
  scale_x_continuous('Magnitude of change in available MAT (C)',
                     limits = c(0, xmx), expand = c(0, 0)) +
  geom_errorbar(aes(ymin = lwr.25., ymax = upr.75.),
                size = 0.5, colour = 'grey40', alpha=0.5) +
  geom_point()
# horizontal error bars don't really make sense -
# how to get these for the absolute difference of mean sample MAT?

# optional: annotate plot with correlation coefficient
  # scatrCor <- cor(resid, absDelta, method='pear')
  # scatrLab <- paste('r =', round(scatrCor, 2))
  # deltaPlot <- deltaPlot +
  #   geom_text(label=scatrLab, size=3, x=xmx*0.8, y=0.45)

# PNAS column width is 8.7 cm (3.4252 in)
if (ss){
  scatrNm <- paste0('Figs/H-vs-delta_0m_',day,'.pdf')
} else {
  scatrNm <- paste0('Figs/H-vs-delta_hab_',day,'.pdf')
}
pdf(scatrNm, width=3.5, height=3.5)
print(deltaPlot)
dev.off()

# Global time series ------------------------------------------------------

# contrast the niche overlap between extreme situations:
# glaciation peak and terminus, for 8 cycles
# (compared to peak vs. peak and terminus vs. terminus)

# find the local max and min global MAT timing in each 100ky interval
ints <- data.frame(yng=c(seq(0,400,by=100), 480, 560), # 690
                   old=c(seq(100,400,by=100), 480, 560, 690) # 800
)
#ints$maxAge <- ints$minAge <- NA
for (r in 1:nrow(ints)){
  bounds <- ints[r,]
  inInt <- which(bins > bounds$yng & bins <= bounds$old)
  minPos <- which.min(globMean[inInt])
  minAge <- bins[inInt[minPos]]
  maxPos <- which.max(globMean[inInt])
  maxAge <- bins[inInt[maxPos]]
  range(globMean[inInt])
  ints[r,c('minAge','maxAge','minT','maxT')] <- 
    c(minAge, maxAge, range(globMean[inInt]))
}

ints$minAge[nrow(ints)] <- NA
ints$maxAge[1] <- NA

# table of glacial max and interglacial peaks

# Lisiecki and Raymo 2005 ages of interglacial onset:
ig <- c(14, 130, 243, 337, 424, 533, 621)
out <- data.frame(glacialMax=ints$minAge, igPeak=ints$maxAge, igOnset=ig)
outx <- xtable(out, align=rep('r', ncol(out)+1), digits=0)
tblNm <- paste0('Figs/glacial-interglacial-ages_',day,'.tex')
if (ss){
  print(outx, file=tblNm, include.rownames=FALSE)
}

# plot time series of global MAT
globDat <- data.frame(bins, globMean) # ,sampAvg)
globTseries <- ggplot() +
  theme_bw() +
  scale_y_continuous('Global MAT (C)') +
  scale_x_continuous('Time (Ka)', expand = c(0, 0),
                     limits = c(-701, 1), breaks = seq(-700, 0, by = 100),
                     labels = paste(seq(700, 0, by = -100))) +
  geom_line(data = globDat, aes(x = -bins, y = globMean)) +
#  geom_line(data=globDat, aes(x=-bins, y=sampAvg),
#            linetype='dashed') 
  geom_point(data = globDat, aes(x = -bins, y = globMean),
             size = 1) +
  geom_point(data = ints, aes(x = -minAge, y = minT), 
             colour = 'deepskyblue', size = 1.5) +
  geom_point(data = ints, aes(x = -maxAge, y = maxT), 
             colour = 'firebrick2', size = 1.5)

# Extreme comparisons -----------------------------------------------------

# prepare a framework of every pairwise comparison to compute
# (every warm vs. cold, warm vs. warm, and cold vs. cold interval)
wc <- expand.grid(X1=ints$minAge[-nrow(ints)], X2=ints$maxAge[-1])
wc$type <- 'cold-warm'
cc <- combn(ints$minAge[-nrow(ints)], 2)
cc <- data.frame(t(cc))
cc$type <- 'cold-cold'
ww <- combn(ints$maxAge[-1], 2)
ww <- data.frame(t(ww))
ww$type <- 'warm-warm'
intPairs <- rbind(wc, cc, ww) 
colnames(intPairs) <- c('t1','t2','type')
comps <- c('cold-cold','warm-warm','cold-warm')
intPairs$type <- factor(intPairs$type, levels = comps)
colr <- c('cold-cold'="deepskyblue",
          'warm-warm'="firebrick2",
          'cold-warm'="purple3")

# inspect the mean delta MAT for each comparison type
globDiff <- function(pair){
  nm1 <- paste0('X', pair['t1'])
  nm2 <- paste0('X', pair['t2'])
  abs(globMean[nm1] - globMean[nm2])
}
intPairs$deltaMAT <- apply(intPairs[,c('t1','t2')], 1, globDiff)
for (typ in comps){
  compBool <- intPairs$type==typ
  compDelt <- intPairs$deltaMAT[compBool]
  mDelt <- round(mean(compDelt),2)
  print(paste(typ, mDelt))
}

pairL <- list()
for (i in 1:nrow(intPairs)){
  b1 <- intPairs$t1[i]
  b2 <- intPairs$t2[i]
  entry <- c(b1, b2)
  pairL <- append(pairL, list(entry))
}

# source('GSA_custom_ecospat_fcns.R')
# source('species_kde_buildr.R')

# warning - this could take 1 - 2 hours
# nCore <- detectCores() - 1
# pkg <- c('pracma','GoFKernel')
# pt1 <- proc.time()
# registerDoParallel(nCore)
# if (ss){
#  kdeSum <- foreach(bPair=pairL, .combine=rbind, .inorder=FALSE, .packages=pkg) %dopar% 
#   kde(truncEnv[[1]], bPair, envNm)
# } else {
# kdeSum <- foreach(dat=truncEnv[2:4], .combine=rbind, .inorder=FALSE, .packages=pkg) %:% 
#  foreach(bPair=pairL, .combine=rbind, .inorder=FALSE, .packages=pkg) %dopar% 
#  kde(dat, bPair, envNm)
# }
# stopImplicitCluster()
# pt2 <- proc.time()
# pt2-pt1
# nas <- is.na(kdeSum$bin)
# kdeSum <- kdeSum[!nas,]
# if (ss){
#  sumNm <- paste0('Data/foram_niche_xtreme_comparisons_0m_',day,'.csv')
# } else {
#  sumNm <- paste0('Data/foram_niche_xtreme_comparisons_hab_',day,'.csv')
# }
# write.csv(kdeSum, sumNm, row.names = FALSE)

# if the script has already been run once, read in the intermediate products instead
if (ss){
 kdeSum <- read.csv('Data/foram_niche_xtreme_comparisons_0m_20-04-07.csv')
} else {
 kdeSum <- read.csv('Data/foram_niche_xtreme_comparisons_hab_20-04-07.csv')
}

# take the mean h for each bin combination
sumH <- function(bPair, dat){
  intBool <- which(dat$bin==bPair[1] & dat$bin2==bPair[2])
  int <- dat[intBool,]
  avgH <- mean(int$h, na.rm=TRUE)
  data.frame(t1=bPair[1], t2=bPair[2], avgH)
}
Hlist <- lapply(pairL, sumH, dat=kdeSum)
Hdf <- do.call(rbind, Hlist)

intPairs <- merge(intPairs, Hdf)
#mxH <- max(intPairs$avgH) * 1.1
ovpBoxs <- ggplot(data=intPairs) +
  theme_bw() +
  scale_y_continuous(name = 'Intraspecific niche H distance',
                     limits=c(0, 0.52), expand=c(0,0)) +
  geom_boxplot(aes(x=type, y=avgH, fill=type)) +
  scale_fill_manual(values=colr) +
  theme(legend.position='none',
        axis.title.x = element_blank())

# Multipanel plots --------------------------------------------------------

if (ss){
  # main text figure
  aligned <- align_plots(globTseries, ovpBoxs, align = 'h', axis = 'l')
  mlti <- plot_grid(
    aligned[[1]], aligned[[2]],
    ncol = 2,
    rel_widths = c(1.66,1),
    labels='AUTO',
    label_size = 12,
    label_x = c(0.16, 0.23),
    vjust=2.3
  )
  
  # full page width is 17.8 cm (7 in)
  panelsNm <- paste0('Figs/H-vs-climate_panels_main_',day,'.pdf')
  pdf(panelsNm, width=7, height=2.5)
  print(mlti)
  dev.off()
  
} else {
  # make supplemental figure: panel B only
  panelsNm <- paste0('Figs/H-vs-climate-extreme_SI_',day,'.pdf')
  pdf(panelsNm, width=3.5, height=3.5)
  print(ovpBoxs)
  dev.off()
}