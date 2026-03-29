
#####  Evolution of Power and Efficiency

# Prediction 1: Total metabolic rate scales as M^(3/4)

M <- 10^seq(-6, 6, length.out = 200)   # body mass range (g)
B0 <- 1                                # normalization constant

B <- B0 * M^(3/4)

plot(M, B, log="xy",
     xlab="Body Mass (M)",
     ylab="Metabolic Rate B(M)",
     main="Prediction 1: Metabolic Scaling B ∝ M^(3/4)",
     pch=16)
abline(a=log10(B0), b=3/4, col="red")

# Prediction 2: Mass specific metabolism

M <- 10^seq(-6, 6, length.out = 200)
B0 <- 1

mass_specific <- B0 * M^(-1/4)

plot(M, mass_specific, log="xy",
     xlab="Body Mass (M)",
     ylab="Metabolism per unit mass",
     main="Prediction 2: Mass-specific metabolism ∝ M^(-1/4)",
     pch=16)
abline(a=log10(B0), b=-1/4, col="blue")


# Prediction 3: Energetic efficiency of biological organization

M <- 10^seq(-3, 9, length.out = 200)

B0 <- 1
Bc <- 10
mc <- 1

e <- 1 - (B0)/(M^(1/4) * (Bc/mc))

plot(M, e, log="x",
     xlab="Body Mass (M)",
     ylab="Energetic Efficiency e(M)",
     main="Prediction 3: Efficiency increases with body size",
     type="l", lwd=3)

abline(h=1, lty=2)



##################

# ---------------------------------------------
# MST efficiency teaching code: e(M) saturates as M^{-1/4}
# ---------------------------------------------

# Mass range (kg)
M <- 10^seq(-12, 6, length.out = 600)

# Parameters (choose values for pedagogy; units cancel in ratios)
Bc_over_mc <- 1        # (Bc/mc): cellular mass-specific metabolic rate (scaled)
B0_vals <- c(0.05, 0.2, 0.8, 3.2)  # lineage metabolic intensity (B0), spanning taxa-like differences

# Theoretical functions
e_fun <- function(M, B0, Bc_over_mc = 1) {
  # e(M) = 1 - (B0 / (Bc/mc)) * M^{-1/4}
  e <- 1 - (B0 / Bc_over_mc) * M^(-1/4)
  # Efficiency must lie in [0,1] for interpretation; truncate for plotting clarity
  pmin(1, pmax(0, e))
}

ineff_fun <- function(M, B0, Bc_over_mc = 1) {
  # 1 - e(M) = (B0 / (Bc/mc)) * M^{-1/4}
  (B0 / Bc_over_mc) * M^(-1/4)
}

B_fun <- function(M, B0, b = 3/4) {
  # Whole-organism metabolic power: B(M) = B0 * M^b
  B0 * M^b
}

# Build long dataframe for plotting
df <- do.call(rbind, lapply(B0_vals, function(B0) {
  data.frame(
    M = M,
    B0 = factor(B0),
    e = e_fun(M, B0, Bc_over_mc),
    ineff = ineff_fun(M, B0, Bc_over_mc),
    B = B_fun(M, B0, b = 3/4),
    B_over_M = B_fun(M, B0, b = 3/4) / M
  )
}))

# ---------------------------------------------
# Plot 1: Efficiency e(M) saturates with size
# ---------------------------------------------
op <- par(no.readonly = TRUE)
par(mfrow = c(1,3), mar = c(4,4,3,1))

cols <- c("black","gray30","gray55","gray75")
names(cols) <- levels(df$B0)

plot(NA, xlim = range(M), ylim = c(0,1),
     log = "x", xlab = "Body mass M (kg)", ylab = "Systemic efficiency e(M)",
     main = "Prediction: e(M) increases\nbut saturates")
for (B0 in levels(df$B0)) {
  d <- df[df$B0 == B0, ]
  lines(d$M, d$e, lwd = 2, col = cols[B0])
}
legend("bottomright", legend = paste0("B0 = ", levels(df$B0)),
       col = cols, lwd = 2, bty = "n")

# ---------------------------------------------
# Plot 2: Inefficiency (1-e) shows the -1/4 law in log space
# ---------------------------------------------
plot(NA, xlim = range(M), ylim = range(df$ineff),
     log = "xy", xlab = "Body mass M (kg)", ylab = "Inefficiency (1 - e)",
     main = "Signature scaling:\n(1-e) ∝ M^{-1/4}")
for (B0 in levels(df$B0)) {
  d <- df[df$B0 == B0, ]
  lines(d$M, d$ineff, lwd = 2, col = cols[B0])
}
# Reference slope line: pick an anchor point and draw a -1/4 line
anchor_M <- 1
anchor_y <- ineff_fun(anchor_M, as.numeric(levels(df$B0)[2]), Bc_over_mc)
ref_M <- 10^seq(-12, 6, length.out = 100)
ref_y <- anchor_y * (ref_M / anchor_M)^(-1/4)
lines(ref_M, ref_y, lwd = 2, lty = 2)  # dashed reference
mtext("dashed: slope = -1/4", side = 3, line = 0.2, cex = 0.9)

# ---------------------------------------------
# Plot 3: Power and mass-specific power move in opposite directions
# ---------------------------------------------
plot(NA, xlim = range(M), ylim = range(df$B),
     log = "xy", xlab = "Body mass M (kg)", ylab = "Metabolic power B(M)",
     main = "Power rises as B ∝ M^{3/4}")
for (B0 in levels(df$B0)) {
  d <- df[df$B0 == B0, ]
  lines(d$M, d$B, lwd = 2, col = cols[B0])
}
# Add a second axis showing mass-specific metabolism B/M ∝ M^{-1/4}
par(new = TRUE)
plot(NA, xlim = range(M), ylim = range(df$B_over_M),
     log = "xy", axes = FALSE, xlab = "", ylab = "")
axis(side = 4)
mtext("Mass-specific metabolism B/M", side = 4, line = 2.5)
for (B0 in levels(df$B0)) {
  d <- df[df$B0 == B0, ]
  lines(d$M, d$B_over_M, lwd = 1.5, col = cols[B0], lty = 3)
}
mtext("dotted: B/M ∝ M^{-1/4}", side = 3, line = 0.2, cex = 0.9)

par(op)

# ---------------------------------------------
# Bonus: quantify diminishing returns
# "How much does efficiency increase if mass increases 10x?"
# ---------------------------------------------
mass_steps <- 10^seq(-10, 5, by = 1)
B0_demo <- B0_vals[3]
delta_e_10x <- e_fun(10*mass_steps, B0_demo, Bc_over_mc) - e_fun(mass_steps, B0_demo, Bc_over_mc)
print(data.frame(M = mass_steps, delta_e_for_10x_increase = delta_e_10x))

###Figure X. Systemic energetic efficiency emerges from metabolic scaling and saturates with body size. Theoretical predictions derived from metabolic scaling theory showing how biological organization generates economies of scale in metabolic dissipation. Left: Systemic efficiency e(M)e(M)e(M) as a function of body mass. Efficiency increases with size because the mass-specific metabolic rate declines as M−1/4M^{-1/4}M−1/4, meaning that larger organisms dissipate less metabolic power per unit biomass. The curves approach a lineage-specific asymptote determined by the ratio B0/(Bc/mc)B_0/(B_c/m_c)B0​/(Bc​/mc​), illustrating that energetic gains from organization saturate at large body sizes. Center: Inefficiency (1−e)(1-e)(1−e) plotted against body mass on log–log axes. The predicted scaling (1−e)∝M−1/4(1-e) \propto M^{-1/4}(1−e)∝M−1/4 produces a straight line with slope −1/4 (dashed line), which reflects the decline in mass-specific metabolic rate with increasing size. Right: Whole-organism metabolic power B(M)=B0M3/4B(M) = B_0 M^{3/4}B(M)=B0​M3/4 increases with body mass (solid lines), while mass-specific metabolism B/M∝M−1/4B/M \propto M^{-1/4}B/M∝M−1/4 declines (dotted lines). Together these relationships illustrate the core theoretical result: integrating biomass into larger organisms reduces metabolic dissipation per unit mass, producing energetic economies of scale, but the benefits of increasing body size diminish because the efficiency correction declines only as M−1/4M^{-1/4}M−1/4. Differences among curves reflect variation in the metabolic normalization constant B0B_0B0​, which captures lineage-level differences in metabolic design independent of body size.







# Prediction 4: Evolutionary shifts in B0 across clades

M <- 10^seq(-3, 6, length.out = 200)

B0_vals <- c(0.5, 1, 2, 4)

plot(M, B0_vals[1]*M^(3/4), log="xy", type="l",
     xlab="Body Mass",
     ylab="Metabolic Rate",
     main="Prediction 4: Clades differ in B0")

for(i in 1:length(B0_vals)){
  lines(M, B0_vals[i]*M^(3/4), lwd=2)
}

legend("topleft",
       legend=paste("B0 =",B0_vals),
       lwd=2)





##########################

library(ggplot2)

# Empirical clade data
clades <- data.frame(
  Taxa = c("Aves","Mammalia","Squamata","Amphibia","Osteichthyes",
           "Insecta","Arachnida","Copepoda","Malacostraca",
           "Gymnolaemata","Oligochaeta","Mollusca","Nematoda",
           "Anthozoa","Protozoa","Unicells"),
  
  b = c(0.68,0.75,0.76,0.77,0.76,
        0.69,0.76,0.72,0.78,
        0.80,0.75,0.75,0.72,
        0.86,0.68,0.79),
  
  B0 = c(3.8,3.59,0.38,0.296,0.287,
         0.3655,0.0859,0.2115,0.308,
         0.308,0.0908,0.159,0.0236,
         0.0738,0.0088,0.0365),
  
  Mmin = c(0.002,0.002,0.0005,0.0005,2e-5,
           7.4e-9,1e-5,1.1e-8,7.4e-7,
           1e-5,2e-8,9.1e-9,7.06e-11,
           8e-11,1e-12,1e-16),
  
  Mmax = c(156,181400,135,25,2000,
           0.1,0.1,9.9e-6,2.8e-4,
           0.1,1.26e-5,250,1.45e-7,
           1e-5,8e-8,4.7e-10)
)

# Generate metabolic scaling curves for each clade
data_list <- lapply(1:nrow(clades), function(i){
  
  M <- exp(seq(log(clades$Mmin[i]),
               log(clades$Mmax[i]),
               length.out=200))
  
  B <- clades$B0[i] * M^(clades$b[i])
  
  data.frame(
    Taxa = clades$Taxa[i],
    M = M,
    B = B,
    Bmass = B/M
  )
})

df <- do.call(rbind, data_list)

# Plot total metabolic scaling
ggplot(df, aes(M, B, color=Taxa)) +
  geom_line(size=1) +
  scale_x_log10() +
  scale_y_log10() +
  labs(x="Body mass (kg)",
       y="Metabolic rate B(M)",
       title="Metabolic scaling across clades") +
  theme_bw()



##Scaling exponents cluster near 3/4

b_vals <- c(0.68,0.75,0.76,0.77,0.76,
            0.69,0.76,0.72,0.78,
            0.80,0.75,0.75,0.72,
            0.86,0.68,0.79)

mean(b_vals)
sd(b_vals)

hist(b_vals,
     main="Distribution of scaling exponents",
     xlab="b",
     col="lightblue")

abline(v=0.75,col="red",lwd=2)




###
library(ggplot2)
library(dplyr)

# Clean data
clades <- data.frame(
  taxa=c("Aves","Mammalia","Squamata","Amphibia","Osteichthyes",
         "Insecta","Arachnida","Copepoda","Malacostraca",
         "Gymnolaemata","Oligochaeta","Mollusca","Nematoda",
         "Anthozoa","Protozoa","Unicells"),
  
  b=c(0.68,0.75,0.76,0.77,0.76,
      0.69,0.76,0.72,0.78,
      0.80,0.75,0.75,0.72,
      0.86,0.68,0.79),
  
  B0=c(3.8,3.59,0.38,0.296,0.287,
       0.3655,0.0859,0.2115,0.308,
       0.308,0.0908,0.159,0.0236,
       0.0738,0.0088,0.0365),
  
  Mmin=c(0.002,0.002,0.0005,0.0005,2e-5,
         7.4e-9,1e-5,1.1e-8,7.4e-7,
         1e-5,2e-8,9.1e-9,7.06e-11,
         8e-11,1e-12,1e-16),
  
  Mmax=c(156,181400,135,25,2000,
         0.1,0.1,9.9e-6,2.8e-4,
         0.1,1.26e-5,250,1.45e-7,
         1e-5,8e-8,4.7e-10)
)

# Remove invalid rows
clades <- clades %>%
  filter(!is.na(Mmin), !is.na(Mmax), Mmin > 0, Mmax > Mmin)

# Generate curves
data_list <- lapply(1:nrow(clades), function(i){
  
  M <- exp(seq(log(clades$Mmin[i]),
               log(clades$Mmax[i]),
               length.out=200))
  
  B <- clades$B0[i] * M^(clades$b[i])
  
  data.frame(
    taxa = clades$taxa[i],
    M = M,
    mass_specific = B/M
  )
})

df <- do.call(rbind, data_list)

ggplot(df, aes(M, mass_specific, color = taxa)) +
  geom_line(size = 1) +
  scale_x_log10() +
  scale_y_log10() +
  labs(x = "Body mass (kg)",
       y = "Mass-specific metabolism (B/M)",
       title = "Energetic envelope of life across clades") +
  theme_bw()


# Corrected MST plot with equal log scaling
ggplot(df, aes(M, mass_specific, color = taxa)) +
  geom_line(linewidth = 1) +
  scale_x_log10() +
  scale_y_log10() +
  coord_fixed() +
  labs(x = "Body mass (kg)",
       y = "Mass-specific metabolism (B/M)",
       title = "Energetic envelope of life across clades") +
  theme_bw()

ggplot(df, aes(M, mass_specific, color = taxa)) +
  geom_line(linewidth = 1) +
  scale_x_log10() +
  scale_y_log10() +
  coord_fixed() +
  annotation_logticks() +
  labs(x = "Body mass (kg)",
       y = "Mass-specific metabolism (B/M)",
       title = "Energetic envelope of life across clades") +
  theme_bw()

###

library(ggplot2)

# Data from your table
rank <- 1:19

taxa <- c("Unicells","Protozoa","Porifera","Anthozoa","Scyphozoa",
          "Nematoda","Mollusca","Branchiopoda","Oligochaeta",
          "Gymnolaemata","Malacostraca","Copepoda","Arachnida",
          "Insecta","Osteichthyes","Amphibia","Squamata",
          "Mammalia","Aves")

B0 <- c(0.0365,0.0088,0.0247,0.0738,0.0135,
        0.0236,0.159,0.0570,0.0908,
        0.308,0.308,0.2115,0.0859,
        0.3655,0.287,0.296,0.380,
        3.59,3.8)

b <- c(0.79,0.68,0.55,0.86,0.85,
       0.72,0.75,0.70,0.75,
       0.80,0.78,0.72,0.76,
       0.69,0.76,0.77,0.76,
       0.75,0.68)

Mmax <- c(4.7e-10,8e-8,NA,1e-5,NA,
          1.45e-7,250,NA,1.26e-5,
          0.1,2.8e-4,9.9e-6,0.1,
          0.1,2000,25,135,
          181400,156)

data <- data.frame(rank,taxa,B0,b,Mmax)

# Remove clades without body size data
data <- na.omit(data)

# Maximum metabolic power
data$Bmax <- data$B0 * data$Mmax^data$b

# Fit exponential model (linear in log space)
fit_M <- lm(log10(Mmax) ~ rank, data=data)
fit_B <- lm(log10(Bmax) ~ rank, data=data)

summary(fit_M)
summary(fit_B)

# Body size vs rank
ggplot(data, aes(rank, Mmax)) +
  geom_point(size=3) +
  geom_smooth(method="lm", se=FALSE) +
  scale_y_log10() +
  labs(x="Rank evolutionary appearance",
       y="Body mass (kg)")

# Metabolic power vs rank
ggplot(data, aes(rank, Bmax)) +
  geom_point(size=3) +
  geom_smooth(method="lm", se=FALSE) +
  scale_y_log10() +
  labs(x="Rank evolutionary appearance",
       y="Metabolic power (W)")

coef(fit_M)[2]
coef(fit_B)[2]

##

fit_M <- lm(log10(Mmax) ~ rank, data=data)
fit_B <- lm(log10(Bmax) ~ rank, data=data)

slope_M <- coef(fit_M)[2]
slope_B <- coef(fit_B)[2]

slope_M
slope_B

slope_B / slope_M

plot(log10(data$Mmax), log10(data$Bmax),
     pch=19,
     xlab="log10 Maximum body mass",
     ylab="log10 Maximum metabolic power")

abline(lm(log10(Bmax) ~ log10(Mmax), data=data), lwd=2)
abline(a=0, b=0.75, col="red", lty=2)





### maximum and minimum size 

library(ggplot2)
library(dplyr)

rank <- 1:19

taxa <- c("Unicells","Protozoa","Porifera","Anthozoa","Scyphozoa",
          "Nematoda","Mollusca","Branchiopoda","Oligochaeta",
          "Gymnolaemata","Malacostraca","Copepoda","Arachnida",
          "Insecta","Osteichthyes","Amphibia","Squamata",
          "Mammalia","Aves")

Mmin <- c(1e-16,1e-12,NA,8e-11,NA,
          7.06e-11,9.1e-9,NA,2e-8,
          1e-5,7.4e-7,1.1e-8,1e-5,
          7.4e-9,2e-5,5e-4,5e-4,
          0.002,0.002)

Mmax <- c(4.7e-10,8e-8,NA,1e-5,NA,
          1.45e-7,250,NA,1.26e-5,
          0.1,2.8e-4,9.9e-6,0.1,
          0.1,2000,25,135,
          181400,156)

df <- data.frame(rank,taxa,Mmin,Mmax)

# remove missing values
df_min <- df %>% filter(!is.na(Mmin))
df_max <- df %>% filter(!is.na(Mmax))


## Fit exponenntial data

fit_min <- lm(log10(Mmin) ~ rank, data=df_min)
fit_max <- lm(log10(Mmax) ~ rank, data=df_max)

summary(fit_min)
summary(fit_max)

coef(fit_min)[2]
coef(fit_max)[2]

##plots
ggplot() +
  
  geom_point(data=df_max,
             aes(rank,Mmax),
             shape=1,
             size=3) +
  
  geom_point(data=df_min,
             aes(rank,Mmin),
             shape=18,
             color="red",
             size=3) +
  
  geom_smooth(data=df_max,
              aes(rank,Mmax),
              method="lm",
              se=FALSE,
              color="black") +
  
  geom_smooth(data=df_min,
              aes(rank,Mmin),
              method="lm",
              se=FALSE,
              color="black") +
  
  scale_y_log10() +
  
  labs(x="Rank Evolutionary Appearance",
       y="Body Mass (kg)") +
  
  theme_bw()

#####
library(ggplot2)
library(dplyr)

rank <- 1:19

taxa <- c("Unicells","Protozoa","Porifera","Anthozoa","Scyphozoa",
          "Nematoda","Mollusca","Branchiopoda","Oligochaeta",
          "Gymnolaemata","Malacostraca","Copepoda","Arachnida",
          "Insecta","Osteichthyes","Amphibia","Squamata",
          "Mammalia","Aves")

Mmin <- c(1e-16,1e-12,NA,8e-11,NA,
          7.06e-11,9.1e-9,NA,2e-8,
          1e-5,7.4e-7,1.1e-8,1e-5,
          7.4e-9,2e-5,5e-4,5e-4,
          0.002,0.002)

Mmax <- c(4.7e-10,8e-8,NA,1e-5,NA,
          1.45e-7,250,NA,1.26e-5,
          0.1,2.8e-4,9.9e-6,0.1,
          0.1,2000,25,135,
          181400,156)

B0 <- c(0.0365,0.0088,0.0247,0.0738,0.0135,
        0.0236,0.159,0.0570,0.0908,
        0.308,0.308,0.2115,0.0859,
        0.3655,0.287,0.296,0.380,
        3.59,3.8)

b <- c(0.79,0.68,0.55,0.86,0.85,
       0.72,0.75,0.70,0.75,
       0.80,0.78,0.72,0.76,
       0.69,0.76,0.77,0.76,
       0.75,0.68)

df <- data.frame(rank,taxa,Mmin,Mmax,B0,b)

df$Bmax <- df$B0 * (df$Mmax^df$b)
df$Bmin <- df$B0 * (df$Mmin^df$b)

##filter missing values
df_max <- df %>% filter(!is.na(Mmax))
df_min <- df %>% filter(!is.na(Mmin))

#Plot 
ggplot() +
  
  geom_point(data=df_max,
             aes(rank,Mmax),
             shape=1,
             size=3) +
  
  geom_point(data=df_min,
             aes(rank,Mmin),
             shape=18,
             color="red",
             size=3) +
  
  geom_smooth(data=df_max,
              aes(rank,Mmax),
              method="lm",
              se=FALSE,
              color="black") +
  
  geom_smooth(data=df_min,
              aes(rank,Mmin),
              method="lm",
              se=FALSE,
              color="black") +
  
  scale_y_log10() +
  
  labs(x="Rank Evolutionary Appearance",
       y="Body Mass (kg)") +
  
  theme_bw()

ggplot() +
  
  geom_point(data=df_max,
             aes(rank,Bmax),
             shape=1,
             size=3) +
  
  geom_point(data=df_min,
             aes(rank,Bmin),
             shape=18,
             color="red",
             size=3) +
  
  geom_smooth(data=df_max,
              aes(rank,Bmax),
              method="lm",
              se=FALSE,
              color="black") +
  
  geom_smooth(data=df_min,
              aes(rank,Bmin),
              method="lm",
              se=FALSE,
              color="black") +
  
  scale_y_log10() +
  
  labs(x="Rank Evolutionary Appearance",
       y="Metabolic Power (Watts)") +
  
  theme_bw()

fit_Mmax <- lm(log10(Mmax) ~ rank, data=df_max)
fit_Mmin <- lm(log10(Mmin) ~ rank, data=df_min)

fit_Bmax <- lm(log10(Bmax) ~ rank, data=df_max)
fit_Bmin <- lm(log10(Bmin) ~ rank, data=df_min)

coef(fit_Mmax)[2]
coef(fit_Mmin)[2]
coef(fit_Bmax)[2]
coef(fit_Bmin)[2]


###
summary(fit_Mmax)
summary(fit_Mmin)
summary(fit_Bmax)
summary(fit_Bmin)

c(
  Mmax_slope = coef(fit_Mmax)[2],
  Mmin_slope = coef(fit_Mmin)[2],
  Bmax_slope = coef(fit_Bmax)[2],
  Bmin_slope = coef(fit_Bmin)[2]
)

coef(fit_Bmax)[2] / coef(fit_Mmax)[2]
coef(fit_Bmin)[2] / coef(fit_Mmin)[2]

confint(fit_Mmax)
confint(fit_Mmin)

confint(fit_Bmax)
confint(fit_Bmin)

coef(fit_Mmax)[2]
confint(fit_Mmax)[2,]

coef(fit_Bmax)[2]
confint(fit_Bmax)[2,]

se_M <- summary(fit_Mmax)$coefficients[2,2]
se_B <- summary(fit_Bmax)$coefficients[2,2]

diff_est <- beta_B - 0.75*beta_M
diff_se <- sqrt(se_B^2 + (0.75^2)*se_M^2)

z <- diff_est / diff_se

p_value <- 2*pnorm(-abs(z))

z
p_value


beta_M <- coef(fit_Mmax)[2]
beta_B <- coef(fit_Bmax)[2]

beta_M
beta_B

beta_pred <- 0.75 * beta_M
beta_pred

beta_B
beta_pred

diff_est <- beta_B - 0.75*beta_M
diff_est

se_M <- summary(fit_Mmax)$coefficients[2,2]
se_B <- summary(fit_Bmax)$coefficients[2,2]

diff_se <- sqrt(se_B^2 + (0.75^2)*se_M^2)

z <- diff_est / diff_se
p_value <- 2*pnorm(-abs(z))

z
p_value

plot(log10(df$Mmax), log10(df$Bmax),
     pch=19,
     xlab="log10 Maximum Body Mass",
     ylab="log10 Maximum Metabolic Power")

abline(lm(log10(Bmax) ~ log10(Mmax), data=df), lwd=2)
abline(a=0, b=0.75, col="red", lwd=2, lty=2)

df_scaling <- df[!is.na(df$Mmax) & !is.na(df$Bmax), ]
fit_scaling <- lm(log10(Bmax) ~ log10(Mmax), data = df_scaling)

summary(fit_scaling)
confint(fit_scaling)


beta_pred <- 0.75

beta_obs
beta_pred

beta_obs - beta_pred

library(car)

linearHypothesis(fit_scaling, "log10(Mmax) = 0.75")

plot(log10(df_scaling$Mmax),
     log10(df_scaling$Bmax),
     pch=19,
     xlab="log10 Maximum Body Mass",
     ylab="log10 Maximum Metabolic Power")

abline(fit_scaling, lwd=2)

abline(a=coef(fit_scaling)[1], b=0.75,
       col="red", lwd=2, lty=2)



######## Compute mass-specific metabolism

Mmin <- c(
  1e-16,
  1e-12,
  NA,
  8e-11,
  NA,
  7.06e-11,
  9.1e-9,
  NA,
  2e-8,
  1e-5,
  7.4e-7,
  1.1e-8,
  1e-5,
  7.4e-9,
  2e-5,
  5e-4,
  5e-4,
  0.002,
  0.002
)

Mmax <- c(
  4.7e-10,
  8e-8,
  NA,
  1e-5,
  NA,
  1.45e-7,
  250,
  NA,
  1.26e-5,
  0.1,
  2.8e-4,
  9.9e-6,
  0.1,
  0.1,
  2000,
  25,
  135,
  181400,
  156
)

summary(df$Bmin)
summary(df$Bmax)

sum(!is.na(df$Bmin/df$Mmin))
sum(!is.na(df$Bmax/df$Mmax))

df$Bmax <- df$B0 * df$Mmax^df$b
df$Bmin <- df$B0 * df$Mmin^df$b

df_env <- df[!is.na(df$Mmin) & !is.na(df$Bmin), ]

df_env_max <- df[!is.na(df$Mmax) & !is.na(df$Bmax), ]


plot(df_env_max$Mmax,
     df_env_max$Bmax/df_env_max$Mmax,
     log="xy",
     pch=1,
     xlab="Body Mass (kg)",
     ylab="Energy per unit mass")

points(df_env$Mmin,
       df_env$Bmin/df_env$Mmin,
       pch=18,
       col="red")



df$Bmax <- df$B0 * (df$Mmax ^ df$b)
df$Bmin <- df$B0 * (df$Mmin ^ df$b)

sum(!is.na(df$Bmax))
sum(!is.na(df$Bmin))

plot(df$Mmax,
     df$Bmax/df$Mmax,
     log="xy",
     pch=1,
     xlab="Body Mass (kg)",
     ylab="Energy per unit mass")

points(df$Mmin,
       df$Bmin/df$Mmin,
       pch=18,
       col="red")


## rebuild

df <- data.frame(
  rank = 1:19,
  
  taxa = c("Unicells","Protozoa","Porifera","Anthozoa","Scyphozoa",
           "Nematoda","Mollusca","Branchiopoda","Oligochaeta",
           "Gymnolaemata","Malacostraca","Copepoda","Arachnida",
           "Insecta","Osteichthyes","Amphibia","Squamata",
           "Mammalia","Aves"),
  
  b = c(0.79,0.68,0.55,0.86,0.85,
        0.72,0.75,0.70,0.75,
        0.80,0.78,0.72,0.76,
        0.69,0.76,0.77,0.76,
        0.75,0.68),
  
  B0 = c(0.0365,0.0088,0.0247,0.0738,0.0135,
         0.0236,0.159,0.0570,0.0908,
         0.3080,0.3080,0.2115,0.0859,
         0.3655,0.2870,0.2960,0.3800,
         3.5900,3.8000),
  
  Mmin = c(
    1e-16,
    1e-12,
    NA,
    8e-11,
    NA,
    7.06e-11,
    9.1e-9,
    NA,
    2e-8,
    1e-5,
    7.4e-7,
    1.1e-8,
    1e-5,
    7.4e-9,
    2e-5,
    5e-4,
    5e-4,
    0.002,
    0.002),
  
  Mmax = c(
    4.7e-10,
    8e-8,
    NA,
    1e-5,
    NA,
    1.45e-7,
    250,
    NA,
    1.26e-5,
    0.1,
    2.8e-4,
    9.9e-6,
    0.1,
    0.1,
    2000,
    25,
    135,
    181400,
    156)
)

df$Bmax <- df$B0 * df$Mmax^df$b
df$Bmin <- df$B0 * df$Mmin^df$b
sum(!is.na(df$Bmax))
sum(!is.na(df$Bmin))

xvals <- c(df$Mmin, df$Mmax)
yvals <- c(df$Bmin/df$Mmin, df$Bmax/df$Mmax)

plot(df$Mmax,
     df$Bmax/df$Mmax,
     log="xy",
     pch=1,
     xlim=range(xvals, na.rm=TRUE),
     ylim=range(yvals, na.rm=TRUE),
     xlab="Body Mass (kg)",
     ylab="Energy per unit mass")

points(df$Mmin,
       df$Bmin/df$Mmin,
       pch=18,
       col="red")

df_env <- df[!is.na(df$Mmax) & !is.na(df$Bmax), ]

fit_env <- lm(log10(Bmax/Mmax) ~ log10(Mmax), data=df_env)

summary(fit_env)

coef(fit_env)[2]
confint(fit_env)

abline(fit_env, lwd=2)

abline(a=coef(fit_env)[1], b=-0.25,
       col="red", lwd=2, lty=2)



##
xvals <- c(df$Mmin, df$Mmax)
yvals <- c(df$Bmin/df$Mmin, df$Bmax/df$Mmax)

plot(df$Mmax,
     df$Bmax/df$Mmax,
     log="xy",
     pch=1,
     xlim=range(xvals, na.rm=TRUE),
     ylim=range(yvals, na.rm=TRUE),
     xlab="Body Mass (kg)",
     ylab="Energy per unit mass")

points(df$Mmin,
       df$Bmin/df$Mmin,
       pch=18,
       col="red")

text(df$Mmax,
     df$Bmax/df$Mmax,
     labels=df$rank,
     pos=4,
     cex=0.8)

text(df$Mmin,
     df$Bmin/df$Mmin,
     labels=df$rank,
     pos=2,
     col="red",
     cex=0.8)

df_env <- df[!is.na(df$Mmax) & !is.na(df$Bmax), ]

fit_emp <- lm(log10(Bmax/Mmax) ~ log10(Mmax), data=df_env)

summary(fit_emp)

beta_emp <- coef(fit_emp)[2]

beta_emp

confint(fit_emp)

plot(df$Mmax,
     df$Bmax/df$Mmax,
     log="xy",
     pch=1,
     xlim=range(c(df$Mmin,df$Mmax),na.rm=TRUE),
     ylim=range(c(df$Bmin/df$Mmin,df$Bmax/df$Mmax),na.rm=TRUE),
     xlab="Body Mass (kg)",
     ylab="Energy per unit mass")

points(df$Mmin,
       df$Bmin/df$Mmin,
       pch=18,
       col="red")

abline(fit_emp, lwd=2)

intercept <- coef(fit_emp)[1]

abline(a=intercept,
       b=-0.25,
       col="red",
       lty=2,
       lwd=2)


#### then both the minimum and maximum metabolic envelopes across clades should follow the same slope:

df_max <- df[!is.na(df$Mmax) & !is.na(df$Bmax), ]
df_min <- df[!is.na(df$Mmin) & !is.na(df$Bmin), ]

fit_max_env <- lm(log10(Bmax/Mmax) ~ log10(Mmax), data=df_max)
summary(fit_max_env)

fit_min_env <- lm(log10(Bmin/Mmin) ~ log10(Mmin), data=df_min)
summary(fit_min_env)

xvals <- c(df$Mmin, df$Mmax)
yvals <- c(df$Bmin/df$Mmin, df$Bmax/df$Mmax)

plot(df_max$Mmax,
     df_max$Bmax/df_max$Mmax,
     log="xy",
     pch=1,
     xlim=range(xvals, na.rm=TRUE),
     ylim=range(yvals, na.rm=TRUE),
     xlab="Body Mass (kg)",
     ylab="Metabolic power per unit mass")

points(df_min$Mmin,
       df_min$Bmin/df_min$Mmin,
       pch=18,
       col="red")

abline(fit_max_env, lwd=2)
abline(fit_min_env, lwd=2)

b_theory <- -0.25

intercept_max <- coef(fit_max_env)[1]
intercept_min <- coef(fit_min_env)[1]

abline(a=intercept_max, b=b_theory, col="blue", lty=2, lwd=2)
abline(a=intercept_min, b=b_theory, col="blue", lty=2, lwd=2)




#####################A basic plot of efficiency vs. body mass for one lineage

# ---- Basic efficiency curve ----
# Choose a range of body masses M
M <- 10^seq(-6, 8, length.out = 300)   # kg, from micro to very large

# Set a baseline B_c/m_c.  This is the per-mass metabolic rate of independent cells.
# Units can be arbitrary as long as consistent; use, say, watts per kg.
Bc_over_mc <- 10   # example baseline, adjust as needed

# Set one lineage's normalization constant B0
B0 <- 1.0          # example value

# Compute efficiency e(M) using the scaling formula
e <- 1 - (B0 / (Bc_over_mc * M^(1/4)))

# Ensure efficiency stays within [0,1] for plotting
e[e < 0] <- 0
e[e > 1] <- 1

# Plot
plot(M, e,
     log = "x",
     type = "l", lwd = 2,
     xlab = "Body mass M (kg, log scale)",
     ylab = "Systemic efficiency e(M)",
     main = "Efficiency vs. body mass for one lineage")

abline(h = 0, col = "gray60")
abline(h = 1, col = "gray60")



################Compare multiple lineages with different  Different taxa may have different baseline metabolic intensities. Plot several curves together to see how  shifts the envelope.


# ---- Compare several B0 values ----
M <- 10^seq(-6, 8, length.out = 300)

Bc_over_mc <- 10

B0_values <- c(0.5, 1, 2, 4)  # examples of increasing metabolic intensity

# Set up plot range
plot(M, rep(0, length(M)),
     log = "x", type = "n",
     xlab = "Body mass M (kg, log scale)",
     ylab = "Systemic efficiency e(M)",
     ylim = c(0, 1),
     main = "Efficiency curves for lineages with different B0")

cols <- rainbow(length(B0_values))

for(i in seq_along(B0_values)){
  B0 <- B0_values[i]
  e <- 1 - (B0 / (Bc_over_mc * M^(1/4)))
  e[e < 0] <- 0
  e[e > 1] <- 1
  lines(M, e, col = cols[i], lwd = 2)
}

legend("bottomright",
       legend = paste("B0 =", B0_values),
       col = cols, lwd = 2)

#Higher B0 lifts the efficiency curve upward for any given mass. A lineage can increase overall power without drastically changing the shape of the size‑efficiency relationship. This visually shows how size increases and shifts in both matter.


####  3) Show the diminishing returns explicitly


# ---- Diminishing returns ----
M <- 10^seq(-6, 8, length.out = 300)
Bc_over_mc <- 10
B0 <- 1

e <- 1 - (B0 / (Bc_over_mc * M^(1/4)))
e[e < 0] <- 0
e[e > 1] <- 1

plot(M, e,
     log = "x", type = "l", lwd = 2,
     xlab = "Body mass M (kg, log scale)",
     ylab = "Efficiency e(M)",
     main = "Diminishing returns from size increases")

# Mark efficiency at a few masses
masses_to_mark <- c(1e-4, 1e0, 1e4, 1e8)
points(masses_to_mark, 1 - (B0 / (Bc_over_mc * masses_to_mark^(1/4))),
       pch = 19, col = "red")
text(masses_to_mark, 1 - (B0 / (Bc_over_mc * masses_to_mark^(1/4))),
     labels = paste0("M=", masses_to_mark),
     pos = 3, cex = 0.7)

## 4) Plot an energetic envelope or band based on empirical clade ranges

# ---- Envelope from clade min/max masses ----
# Example clades data frame (replace with your actual data)
clades <- data.frame(
  taxa = c("CladeA", "CladeB"),
  B0   = c(1.0, 2.0),
  MMin = c(1e-6, 1e-3),
  MMax = c(1e3, 1e6)
)

Bc_over_mc <- 10

# Plot the background envelope
plot(NULL, NULL,
     log = "x", xlim = c(1e-6, 1e8), ylim = c(0, 1),
     xlab = "Body mass M (kg)",
     ylab = "Systemic efficiency e(M)",
     main = "Clade envelopes from min to max mass")

colors <- rainbow(nrow(clades))

for(i in 1:nrow(clades)){
  B0 <- clades$B0[i]
  M_range <- seq(log10(clades$MMin[i]), log10(clades$MMax[i]), length.out = 200)
  M_range <- 10^M_range
  e <- 1 - (B0 / (Bc_over_mc * M_range^(1/4)))
  e[e < 0] <- 0
  e[e > 1] <- 1
  lines(M_range, e, col = colors[i], lwd = 2)
}

legend("bottomright",
       legend = clades$taxa,
       col = colors, lwd = 2)

##

# ---- Mass-specific metabolism band ----
M <- 10^seq(-6, 8, length.out = 300)

# Several B0 values to form a band
B0_vals <- c(0.5, 1, 2, 4)
cols <- rainbow(length(B0_vals))

plot(NULL, NULL,
     log = "xy",
     xlim = c(1e-6, 1e8),
     ylim = c(1e-2, 1e2),
     xlab = "Body mass M (kg)",
     ylab = "Mass-specific metabolism B/M",
     main = "Band of mass-specific metabolism curves")

for(i in seq_along(B0_vals)){
  B0 <- B0_vals[i]
  mass_spec <- B0 * M^(-1/4)
  lines(M, mass_spec, col = cols[i], lwd = 2)
}

legend("topright",
       legend = paste("B0 =", B0_vals),
       col = cols, lwd = 2)


######################
######################
######################
######################

# Global metabolic rate data https://www.pnas.org/doi/10.1073/pnas.2303764120#supplementary-materials

# adjust the path to where the file actually resides

file_path <- "/Users/brianjenquist/Desktop/Hoehler_etal_PNAS_MetabolicRateData_For_R.csv"

library(readr)

df <- read_csv(file_path)

glimpse(df)          # from dplyr or tibble
head(df)
summary(df)
library(ggplot2)

df <- df %>%
  mutate(mass_specific_power = Metabolic_Rate_W_at_25_C / Dry_Mass_g)

ggplot(df, aes(x = Dry_Mass_g, y = mass_specific_power)) +
  geom_point() +
  scale_x_log10() +
  scale_y_log10() +
  labs(
    x = "Body mass (kg)",
    y = "Mass-specific metabolic power (W kg^-1)",
    title = "Energetic envelope from Hoehler et al. dataset"
  )


# log transform
df <- df %>%
  mutate(
    log_mass = log10(Dry_Mass_g),
    log_mass_specific = log10(mass_specific_power)
  )

# fit scaling relationship
fit <- lm(log_mass_specific ~ log_mass, data = df)

summary(fit)
coef(fit)

#Extract the slope:
beta_obs <- coef(fit)[2]
beta_obs

#Compare to theory:

beta_theory <- -0.25
beta_obs
beta_theory

# Plot empirical scaling with theoretical prediction

ggplot(df, aes(x = Dry_Mass_g, y = mass_specific_power)) +
  geom_point(alpha = 0.6) +
  scale_x_log10() +
  scale_y_log10() +
  geom_smooth(method = "lm", color = "black", se = FALSE) +
  stat_function(
    fun = function(x) {
      10^(coef(fit)[1]) * x^(-0.25)
    },
    color = "red",
    linetype = "dashed"
  ) +
  labs(
    x = "Body mass (g)",
    y = "Mass-specific metabolic power (W g^-1)",
    title = "Scaling of mass-specific metabolism across organisms",
    subtitle = "Black = empirical fit, Red dashed = MST prediction (-1/4)"
  )

## Construct the energetic envelope Now we compute the upper and lower bounds of mass-specific metabolism.

df_bins <- df %>%
  mutate(size_bin = cut(log_mass, breaks = 20))

envelope <- df_bins %>%
  group_by(size_bin) %>%
  summarise(
    mass = mean(Dry_Mass_g, na.rm = TRUE),
    max_power = max(mass_specific_power, na.rm = TRUE),
    min_power = min(mass_specific_power, na.rm = TRUE)
  )
library(dplyr)

library(tidyverse)

df <- df %>%
  mutate(
    mass_specific_power = Metabolic_Rate_W_at_25_C / Dry_Mass_g,
    log_mass = log10(Dry_Mass_g),
    log_metabolism = log10(Metabolic_Rate_W_at_25_C),
    log_mass_specific = log10(mass_specific_power)
  ) %>%
  filter(
    is.finite(log_mass),
    is.finite(log_metabolism),
    is.finite(log_mass_specific)
  )

# Global scaling relationships
fit_total <- lm(log_metabolism ~ log_mass, data=df)
summary(fit_total)
confint(fit_total)

#mass specific metabolism
fit_specific <- lm(log_mass_specific ~ log_mass, data=df)
summary(fit_specific)
confint(fit_specific)

#Plot scaling colored by taxonomic group
#Domain-level organization

ggplot(df, aes(Dry_Mass_g, Metabolic_Rate_W_at_25_C, color=Domain)) +
  geom_point(alpha=0.6) +
  scale_x_log10() +
  scale_y_log10() +
  labs(
    x="Body mass (g)",
    y="Metabolic rate (W)",
    title="Metabolic scaling across domains of life"
  )

#Phylum-level organization

ggplot(df, aes(Dry_Mass_g, Metabolic_Rate_W_at_25_C, color=Phylum)) +
  geom_point(alpha=0.6) +
  scale_x_log10() +
  scale_y_log10() +
  labs(
    x="Body mass (g)",
    y="Metabolic rate (W)",
    title="Metabolic scaling across Phyla of life"
  )

## Only plot fitted regression lines

#Estimate scaling slopes by taxonomic level

phylum_slopes <- df %>%
  group_by(Phylum) %>%
  filter(n() > 10) %>%
  summarise(
    slope_B = coef(lm(log_metabolism ~ log_mass))[2],
    slope_BM = coef(lm(log_mass_specific ~ log_mass))[2],
    n = n()
  )

phylum_slopes


#Class-level organization

ggplot(df, aes(Dry_Mass_g, Metabolic_Rate_W_at_25_C, color=Class)) +
  geom_point(alpha=0.6) +
  scale_x_log10() +
  scale_y_log10() +
  labs(
    x="Body mass (g)",
    y="Metabolic rate (W)",
    title="Metabolic scaling across Classes of life"
  )


#Class-level scaling
class_slopes <- df %>%
  group_by(Class) %>%
  filter(n() > 10) %>%
  summarise(
    slope_B = coef(lm(log_metabolism ~ log_mass))[2],
    slope_BM = coef(lm(log_mass_specific ~ log_mass))[2],
    n = n()
  )

class_slopes

#Order-level
order_slopes <- df %>%
  group_by(Order) %>%
  filter(n() > 10) %>%
  summarise(
    slope_B = coef(lm(log_metabolism ~ log_mass))[2],
    slope_BM = coef(lm(log_mass_specific ~ log_mass))[2],
    n = n()
  )

order_slopes

#visualize slopes

#class distributions
ggplot(class_slopes, aes(x=slope_B)) +
  geom_histogram(bins=30, fill="steelblue") +
  geom_vline(xintercept=0.75, color="red", linewidth=1.2) +
  labs(
    x="Slope of B vs M",
    y="Frequency",
    title="Distribution of metabolic scaling exponents across classes"
  )

ggplot(class_slopes, aes(x=slope_BM)) +
  geom_histogram(bins=20, fill="darkgreen") +
  geom_vline(xintercept=-0.25, color="red", linewidth=1.2) +
  labs(
    x="Slope of B/M vs M",
    y="Frequency",
    title="Distribution of mass-specific metabolic scaling exponents across classes"
  )


#order distributions
ggplot(order_slopes, aes(x=slope_B)) +
  geom_histogram(bins=20, fill="steelblue") +
  geom_vline(xintercept=0.75, color="red", linewidth=1.2) +
  labs(
    x="Slope of B vs M",
    y="Frequency",
    title="Distribution of metabolic scaling exponents across Orders"
  )

ggplot(order_slopes, aes(x=slope_BM)) +
  geom_histogram(bins=20, fill="darkgreen") +
  geom_vline(xintercept=-0.25, color="red", linewidth=1.2) +
  labs(
    x="Slope of B/M vs M",
    y="Frequency",
    title="Distribution of mass-specific metabolic scaling exponents acros orders"
  )

#Energetic envelopes
df_bins <- df %>%
  mutate(size_bin = cut(log_mass, breaks=25))

envelope <- df_bins %>%
  group_by(size_bin, Phylum) %>%
  summarise(
    mass = mean(Dry_Mass_g),
    max_power = max(mass_specific_power),
    min_power = min(mass_specific_power)
  )

ggplot(df, aes(Dry_Mass_g, mass_specific_power)) +
  geom_point(alpha=0.2) +
  geom_line(data=envelope,
            aes(mass, max_power, color=Phylum),
            linewidth=1) +
  #geom_line(data=envelope,
            #aes(mass, min_power, color=Phylum),
            #linewidth=1) +
  scale_x_log10() +
  scale_y_log10() +
  labs(
    x="Body mass (g)",
    y="Mass-specific metabolic power",
    title="Energetic envelopes across phyla"
  )


### REMOVE ALL UNICELLS - MULTICELLULAR ANALYSES
df_multicellular <- df %>%
  filter(
    !(Domain %in% c("Bacteria", "Archaea")),
    !(Phylum %in% c(
      "Cyanobacteria",
      "Chlorophyta",
      "Bacillariophyta",
      "Dinoflagellata",
      "Protozoa"
    ))
  )

table(df_multicellular$Domain)
table(df_multicellular$Phylum)

# recalculate log values
df_multicellular <- df_multicellular %>%
  mutate(
    mass_specific_power = Metabolic_Rate_W_at_25_C / Dry_Mass_g,
    log_mass = log10(Dry_Mass_g),
    log_metabolism = log10(Metabolic_Rate_W_at_25_C),
    log_mass_specific = log10(mass_specific_power)
  ) %>%
  filter(
    is.finite(log_mass),
    is.finite(log_metabolism),
    is.finite(log_mass_specific)
  )

fit_total_multi <- lm(log_metabolism ~ log_mass, data=df_multicellular)

summary(fit_total_multi)
confint(fit_total_multi)

coef(fit_total_multi)[2]

fit_specific_multi <- lm(log_mass_specific ~ log_mass,
                         data=df_multicellular)

summary(fit_specific_multi)
confint(fit_specific_multi)

ggplot(df_multicellular,
       aes(Dry_Mass_g, Metabolic_Rate_W_at_25_C)) +
  geom_point(alpha=0.6) +
  geom_smooth(method="lm", se=FALSE, color="black") +
  scale_x_log10() +
  scale_y_log10() +
  labs(
    x="Body mass (g)",
    y="Metabolic rate (W)",
    title="Metabolic scaling in multicellular organisms"
  )

ggplot(df_multicellular,
       aes(Dry_Mass_g, mass_specific_power)) +
  geom_point(alpha=0.6) +
  geom_smooth(method="lm", se=FALSE, color="black") +
  scale_x_log10() +
  scale_y_log10() +
  labs(
    x="Body mass (g)",
    y="Mass-specific metabolic power",
    title="Mass-specific metabolism in multicellular organisms"
  )
coef(fit_total)[2]          # all life
coef(fit_total_multi)[2]    # multicellular only



#Phylum-level organization

ggplot(df_multicellular, aes(Dry_Mass_g, Metabolic_Rate_W_at_25_C, color=Phylum)) +
  geom_point(alpha=0.6) +
  scale_x_log10() +
  scale_y_log10() +
  labs(
    x="Body mass (g)",
    y="Metabolic rate (W)",
    title="Metabolic scaling across multicellular Phyla of life"
  )

#Estimate scaling slopes by taxonomic level

phylum_slopes_multicellular <- df_multicellular %>%
  group_by(Phylum) %>%
  filter(n() > 10) %>%
  summarise(
    slope_B = coef(lm(log_metabolism ~ log_mass))[2],
    slope_BM = coef(lm(log_mass_specific ~ log_mass))[2],
    n = n()
  )

phylum_slopes_multicellular


#Class-level organization

ggplot(df_multicellular, aes(Dry_Mass_g, Metabolic_Rate_W_at_25_C, color=Class)) +
  geom_point(alpha=0.6) +
  scale_x_log10() +
  scale_y_log10() +
  labs(
    x="Body mass (g)",
    y="Metabolic rate (W)",
    title="Metabolic scaling across multicellular Classes of life"
  )


#Class-level scaling
class_slopes_multicellular <- df_multicellular %>%
  group_by(Class) %>%
  filter(n() > 10) %>%
  summarise(
    slope_B = coef(lm(log_metabolism ~ log_mass))[2],
    slope_BM = coef(lm(log_mass_specific ~ log_mass))[2],
    n = n()
  )

class_slopes_multicellular

#Order-level
order_slopes_multicelluar <- df_multicellular %>%
  group_by(Order) %>%
  filter(n() > 10) %>%
  summarise(
    slope_B = coef(lm(log_metabolism ~ log_mass))[2],
    slope_BM = coef(lm(log_mass_specific ~ log_mass))[2],
    n = n()
  )

order_slopes_multicellular

#visualize slopes

#class distributions
ggplot(class_slopes_multicellular, aes(x=slope_B)) +
  geom_histogram(bins=30, fill="steelblue") +
  geom_vline(xintercept=0.75, color="red", linewidth=1.2) +
  labs(
    x="Slope of B vs M",
    y="Frequency",
    title="Distribution of multicellular metabolic scaling exponents across classes"
  )

ggplot(class_slopes_multicellular, aes(x=slope_BM)) +
  geom_histogram(bins=20, fill="darkgreen") +
  geom_vline(xintercept=-0.25, color="red", linewidth=1.2) +
  labs(
    x="Slope of B/M vs M",
    y="Frequency",
    title="Distribution of mass-specific metabolic scaling exponents across classes"
  )


#order distributions
ggplot(order_slopes_multicelluar, aes(x=slope_B)) +
  geom_histogram(bins=20, fill="steelblue") +
  geom_vline(xintercept=0.75, color="red", linewidth=1.2) +
  labs(
    x="Slope of B vs M",
    y="Frequency",
    title="Distribution of multicellular metabolic scaling exponents across Orders"
  )

ggplot(order_slopes_multicelluar, aes(x=slope_BM)) +
  geom_histogram(bins=20, fill="darkgreen") +
  geom_vline(xintercept=-0.25, color="red", linewidth=1.2) +
  labs(
    x="Slope of B/M vs M",
    y="Frequency",
    title="Distribution of mass-specific multicellular metabolic scaling exponents acros orders"
  )

#Energetic envelopes
library(dplyr)
library(ggplot2)

# Bin by log10 mass
df_bins <- df_multicellular %>%
  mutate(size_bin = cut(log_mass, breaks = 10, include.lowest = TRUE))

# Envelope per bin x phylum
envelope <- df_bins %>%
  group_by(size_bin, Class) %>%
  summarise(
    # better "center" of the bin on log axes:
    mass = 10^(mean(log_mass, na.rm = TRUE)),
    max_power = max(mass_specific_power, na.rm = TRUE),
    min_power = min(mass_specific_power, na.rm = TRUE),
    n = dplyr::n(),
    .groups = "drop"
  ) %>%
  # drop bins with too few points if you want (helps jagged lines)
  filter(n >= 3)

ggplot(df_multicellular, aes(Dry_Mass_g, mass_specific_power)) +
  geom_point(alpha = 0.2) +
  geom_line(data = envelope,
            aes(x = mass, y = max_power, color = Class, group = Class),
            linewidth = 1) +
  geom_line(data = envelope,
            aes(x = mass, y = min_power, color = Class, group = Class),
            linewidth = 1) +
  scale_x_log10() +
  scale_y_log10() +
  labs(
    x = "Body mass (g)",
    y = "Mass-specific metabolic power (W g^-1)",
    title = "Energetic envelopes across phyla"
  )

### Frequency distriubiton 

library(dplyr)
library(ggplot2)

df_plot <- df_multicellular %>%
  mutate(
    Dry_Mass_kg = Dry_Mass_g / 1000,
    ms_power_Wkg = Metabolic_Rate_W_at_25_C / Dry_Mass_kg
  ) %>%
  filter(is.finite(ms_power_Wkg), ms_power_Wkg > 0) %>%
  mutate(log10_ms_power = log10(ms_power_Wkg))

mu <- mean(df_plot$log10_ms_power, na.rm = TRUE)

ggplot(df_plot, aes(x = log10_ms_power)) +
  geom_density(linewidth = 1) +
  geom_vline(xintercept = mu, linetype = "dotted", linewidth = 1) +
  labs(
    x = expression(log[10]*" mass-specific metabolic power (W kg"^{-1}*")"),
    y = "Density",
    title = "Distribution of mass-specific metabolic power across multicellular taxa"
  )

#Compare distributions across Phylum / Class / Order A) Faceted densities (best for readability)


plot_faceted_density <- function(df, group_var, min_n = 20) {
  df2 <- df %>%
    filter(!is.na(.data[[group_var]])) %>%
    group_by(.data[[group_var]]) %>%
    mutate(n_group = n()) %>%
    ungroup() %>%
    filter(n_group >= min_n)
  
  ggplot(df2, aes(x = log10_ms_power)) +
    geom_density(linewidth = 0.8) +
    geom_vline(xintercept = mean(df2$log10_ms_power, na.rm = TRUE),
               linetype = "dotted", linewidth = 0.8) +
    facet_wrap(as.formula(paste("~", group_var)), scales = "free_y") +
    labs(
      x = expression(log[10]*" mass-specific metabolic power (W kg"^{-1}*")"),
      y = "Density",
      title = paste("Distributions of mass-specific metabolic power by", group_var),
      subtitle = paste("Showing groups with n >=", min_n)
    )
}

plot_faceted_density(df_plot, "Phylum", min_n = 30)
plot_faceted_density(df_plot, "Class",  min_n = 30)
plot_faceted_density(df_plot, "Order",  min_n = 30)

#Overlaid densities (works for Phylum; gets messy for many Orders)
df_phylum <- df_plot %>%
  filter(!is.na(Phylum)) %>%
  group_by(Phylum) %>%
  mutate(n_group = n()) %>%
  ungroup() %>%
  filter(n_group >= 30)

ggplot(df_phylum, aes(x = log10_ms_power, color = Phylum)) +
  geom_density(linewidth = 0.8, alpha = 0.6) +
  geom_vline(xintercept = mean(df_phylum$log10_ms_power, na.rm = TRUE),
             linetype = "dotted", linewidth = 0.8) +
  labs(
    x = expression(log[10]*" mass-specific metabolic power (W kg"^{-1}*")"),
    y = "Density",
    title = "Overlaid distributions by Phylum",
    subtitle = "Filtered to phyla with n >= 30"
  )

#If you really want overlay for Class/Order: plot only the top N groups

overlay_topN <- function(df, group_var, topN = 12) {
  top_groups <- df %>%
    filter(!is.na(.data[[group_var]])) %>%
    count(.data[[group_var]], sort = TRUE) %>%
    slice_head(n = topN) %>%
    pull(.data[[group_var]])
  
  df2 <- df %>% filter(.data[[group_var]] %in% top_groups)
  
  ggplot(df2, aes(x = log10_ms_power, color = .data[[group_var]])) +
    geom_density(linewidth = 0.8, alpha = 0.6) +
    geom_vline(xintercept = mean(df2$log10_ms_power, na.rm = TRUE),
               linetype = "dotted", linewidth = 0.8) +
    labs(
      x = expression(log[10]*" mass-specific metabolic power (W kg"^{-1}*")"),
      y = "Density",
      title = paste("Overlaid distributions by", group_var),
      subtitle = paste("Top", topN, "groups by sample size")
    )
}

overlay_topN(df_plot, "Class", topN = 12)
overlay_topN(df_plot, "Order", topN = 12)




#####
#####
#####


make_group_lines <- function(df, group_var, y_var,
                             x_var = "Dry_Mass_kg",
                             min_n = 20,
                             grid_n = 200){
  
  library(dplyr)
  
  df %>%
    filter(!is.na(.data[[group_var]])) %>%
    group_by(.data[[group_var]]) %>%
    filter(n() >= min_n) %>%
    group_modify(function(d, key){
      
      # fit regression in log space
      fit <- lm(log10(d[[y_var]]) ~ log10(d[[x_var]]))
      
      a <- coef(fit)[1]
      b <- coef(fit)[2]
      
      # generate mass grid
      mass_grid <- 10^seq(
        log10(min(d[[x_var]])),
        log10(max(d[[x_var]])),
        length.out = grid_n
      )
      
      # predicted metabolic values
      yhat <- 10^(a + b * log10(mass_grid))
      
      tibble(
        group = key[[1]],
        mass = mass_grid,
        yhat = yhat,
        slope = b,
        intercept = a
      )
    }) %>%
    ungroup()
}

plot_lines_only <- function(lines_df, title, ylab, facet = TRUE){
  
  library(ggplot2)
  
  p <- ggplot(lines_df,
              aes(x = mass, y = yhat,
                  color = group,
                  group = group)) +
    geom_line(linewidth = 1) +
    scale_x_log10() +
    scale_y_log10() +
    labs(
      x = "Body mass (kg)",
      y = ylab,
      title = title
    )
  
  if(facet){
    p <- p + facet_wrap(~group, scales="free_y")
  }
  
  p
}

lines_B_phylum  <- make_group_lines(df0, "Phylum", "B_W")
lines_ms_phylum <- make_group_lines(df0, "Phylum", "ms_power_Wkg")

plot_lines_only(
  lines_B_phylum,
  "Metabolic rate scaling by Phylum",
  "Metabolic rate (W)"
)

plot_lines_only(
  lines_ms_phylum,
  "Mass-specific metabolic scaling by Phylum",
  "Mass-specific metabolic power (W kg^-1)"
)







make_group_lines <- function(df, group_var, y_var,
                             x_var = "Dry_Mass_kg",
                             min_n = 20,
                             grid_n = 200){
  
  
  
  
  library(dplyr)
  
  # global mass range
  mass_grid <- 10^seq(
    log10(min(df[[x_var]], na.rm=TRUE)),
    log10(max(df[[x_var]], na.rm=TRUE)),
    length.out = grid_n
  )
  
  df %>%
    filter(!is.na(.data[[group_var]])) %>%
    group_by(.data[[group_var]]) %>%
    filter(n() >= min_n) %>%
    group_modify(function(d, key){
      
      fit <- lm(log10(d[[y_var]]) ~ log10(d[[x_var]]))
      
      a <- coef(fit)[1]
      b <- coef(fit)[2]
      
      yhat <- 10^(a + b * log10(mass_grid))
      
      tibble(
        group = key[[1]],
        mass = mass_grid,
        yhat = yhat,
        slope = b
      )
    }) %>%
    ungroup()
}

lines_B_phylum  <- make_group_lines(df0, "Phylum", "B_W")
lines_B_class   <- make_group_lines(df0, "Class", "B_W")
lines_B_order   <- make_group_lines(df0, "Order", "B_W")

lines_ms_phylum <- make_group_lines(df0, "Phylum", "ms_power_Wkg")
lines_ms_class  <- make_group_lines(df0, "Class", "ms_power_Wkg")
lines_ms_order  <- make_group_lines(df0, "Order", "ms_power_Wkg")

ggplot(lines_B_order,
#ggplot(lines_B_class,
#ggplot(lines_B_phylum,
       aes(mass, yhat, color=group)) +
  geom_line(linewidth=1.2) +
  scale_x_log10() +
  scale_y_log10() +
  labs(
    x="Body mass (kg)",
    y="Metabolic rate (W)",
    title="Metabolic scaling across Orders"
  )

ggplot(lines_ms_order,
#ggplot(lines_ms_class,
#ggplot(lines_ms_phylum,
       aes(mass, yhat, color=group)) +
  geom_line(linewidth=1.2) +
  scale_x_log10() +
  scale_y_log10() +
  labs(
    x="Body mass (kg)",
    y="Mass-specific metabolic power (W kg^-1)",
    title="Mass-specific metabolic scaling across Orders"
  )


#################################
#################################
#################################

make_group_lines <- function(df, group_var, y_var,
                             x_var = "Dry_Mass_kg",
                             min_n = 20,
                             grid_n = 200){
  
  library(dplyr)
  
  df %>%
    filter(!is.na(.data[[group_var]])) %>%
    group_by(.data[[group_var]]) %>%
    filter(n() >= min_n) %>%
    group_modify(function(d, key){
      
      # fit scaling relationship
      fit <- lm(log10(d[[y_var]]) ~ log10(d[[x_var]]))
      
      a <- coef(fit)[1]
      b <- coef(fit)[2]
      
      # group-specific size range
      mass_grid <- 10^seq(
        log10(min(d[[x_var]], na.rm=TRUE)),
        log10(max(d[[x_var]], na.rm=TRUE)),
        length.out = grid_n
      )
      
      yhat <- 10^(a + b * log10(mass_grid))
      
      tibble(
        group = key[[1]],
        mass = mass_grid,
        yhat = yhat,
        slope = b
      )
    }) %>%
    ungroup()
}
lines_B_phylum  <- make_group_lines(df0, "Phylum", "B_W")
lines_B_class   <- make_group_lines(df0, "Class", "B_W")
lines_B_order   <- make_group_lines(df0, "Order", "B_W")

lines_ms_phylum <- make_group_lines(df0, "Phylum", "ms_power_Wkg")
lines_ms_class  <- make_group_lines(df0, "Class", "ms_power_Wkg")
lines_ms_order  <- make_group_lines(df0, "Order", "ms_power_Wkg")

ggplot(lines_B_order,
#ggplot(lines_B_class,
#ggplot(lines_B_phylum,
       aes(x = mass, y = yhat, color = group)) +
  geom_line(linewidth = 1.2) +
  scale_x_log10() +
  scale_y_log10() +
  labs(
    x = "Body mass (kg)",
    y = "Metabolic rate (W)",
    title = "Metabolic scaling across Orders"
  )

ggplot(lines_ms_order,
#ggplot(lines_ms_class,
#ggplot(lines_ms_phylum,
       aes(x = mass, y = yhat, color = group)) +
  geom_line(linewidth = 1.2) +
  scale_x_log10() +
  scale_y_log10() +
  labs(
    x = "Body mass (kg)",
    y = "Mass-specific metabolic power (W kg⁻¹)",
    title = "Mass-specific metabolic scaling across Orders"
  )




#############################



library(dplyr)

get_scaling_exponents <- function(df, group_var, y_var="B_W", x_var="Dry_Mass_kg", min_n=10){
  
  df %>%
    filter(!is.na(.data[[group_var]])) %>%
    group_by(.data[[group_var]]) %>%
    filter(n() >= min_n) %>%
    summarise(
      n = n(),
      slope = coef(lm(log10(.data[[y_var]]) ~ log10(.data[[x_var]])))[2],
      intercept = coef(lm(log10(.data[[y_var]]) ~ log10(.data[[x_var]])))[1]
    ) %>%
    rename(group = !!group_var) %>%
    ungroup()
}

exp_phylum <- get_scaling_exponents(df0, "Phylum")
exp_class <- get_scaling_exponents(df0, "Class")
exp_order <- get_scaling_exponents(df0, "Order")


library(ggplot2)

ggplot(exp_phylum, aes(x=slope)) +
  geom_histogram(aes(y=..density..), bins=15, fill="grey80", color="black") +
  geom_density(linewidth=1.2) +
  geom_vline(xintercept=0.75, linetype="dashed", linewidth=1) +
  labs(
    x="Metabolic scaling exponent (b)",
    y="Density",
    title="Distribution of metabolic scaling exponents across phyla"
  )

exp_phylum$level <- "Phylum"
exp_class$level  <- "Class"
exp_order$level  <- "Order"

exp_all <- bind_rows(exp_phylum, exp_class, exp_order)

ggplot(exp_all, aes(x=slope, fill=level)) +
  geom_density(alpha=0.4) +
  geom_vline(xintercept=0.75, linetype="dashed") +
  labs(
    x="Metabolic scaling exponent (b)",
    y="Density",
    title="Distribution of metabolic scaling exponents across taxonomic levels"
  )

exp_all %>%
  group_by(level) %>%
  summarise(
    mean_slope = mean(slhttps://chatgpt.com/c/69a4bdf6-975c-832b-8b5b-0d523d0dd4d2ope),
    sd_slope = sd(slope),
    min_slope = min(slope),
    max_slope = max(slope)
  )




##############
##Function to filter taxa by size range

filter_size_range <- function(df, group_var, x_var="Dry_Mass_kg", min_orders=3){
  
  library(dplyr)
  
  df %>%
    group_by(.data[[group_var]]) %>%
    mutate(
      min_mass = min(.data[[x_var]], na.rm=TRUE),
      max_mass = max(.data[[x_var]], na.rm=TRUE),
      orders = log10(max_mass/min_mass)
    ) %>%
    ungroup() %>%
    filter(orders >= min_orders)
}

df_phylum <- filter_size_range(df0, "Phylum")
df_class <- filter_size_range(df0, "Class")
df_order <- filter_size_range(df0, "Order")
df_family <- filter_size_range(df0, "Family")
df_genus <- filter_size_range(df0, "Genus")

exp_phylum <- get_scaling_exponents(df_phylum, "Phylum")
exp_class  <- get_scaling_exponents(df_class, "Class")
exp_order  <- get_scaling_exponents(df_order, "Order")
exp_family  <- get_scaling_exponents(df_order, "Family")
exp_genus  <- get_scaling_exponents(df_order, "Genus")

exp_phylum$level <- "Phylum"
exp_class$level  <- "Class"
exp_order$level  <- "Order"
exp_family$level  <- "Family"
exp_genus$level  <- "Genus"

exp_all <- bind_rows(exp_phylum, exp_class, exp_order, exp_family, exp_genus)

ggplot(exp_all, aes(x=slope, fill=level)) +
  geom_density(alpha=0.4) +
  geom_vline(xintercept=0.75, linetype="dashed") +
  labs(
    x="Metabolic scaling exponent (b)",
    y="Density",
    title="Distribution of metabolic scaling exponents (groups with ≥3 orders of mass)"
  )

exp_all %>%
  group_by(level) %>%
  summarise(
    n_groups = n(),
    mean_slope = mean(slope),
    sd_slope = sd(slope)
  )


get_scaling_exponents <- function(df, group_var,
                                  y_var="B_W",
                                  x_var="Dry_Mass_kg",
                                  min_n=10){
  
  library(dplyr)
  
  df %>%
    filter(!is.na(.data[[group_var]])) %>%
    group_by(.data[[group_var]]) %>%
    filter(n() >= min_n) %>%
    summarise(
      n = n(),
      slope = coef(lm(log10(.data[[y_var]]) ~ log10(.data[[x_var]])))[2]
    ) %>%
    rename(group = !!group_var) %>%
    ungroup()
}



slope_summary <- function(exp_df){
  
  n <- nrow(exp_df)
  mean_slope <- mean(exp_df$slope)
  sd_slope <- sd(exp_df$slope)
  
  se <- sd_slope / sqrt(n)
  tcrit <- qt(0.975, df = n-1)
  
  ci_lower <- mean_slope - tcrit * se
  ci_upper <- mean_slope + tcrit * se
  
  data.frame(
    n_groups = n,
    mean_slope = mean_slope,
    sd = sd_slope,
    CI_lower = ci_lower,
    CI_upper = ci_upper
  )
}

slope_summary <- function(exp_df){
  
  n <- nrow(exp_df)
  mean_slope <- mean(exp_df$slope)
  sd_slope <- sd(exp_df$slope)
  
  se <- sd_slope / sqrt(n)
  tcrit <- qt(0.975, df = n-1)
  
  ci_lower <- mean_slope - tcrit * se
  ci_upper <- mean_slope + tcrit * se
  
  data.frame(
    n_groups = n,
    mean_slope = mean_slope,
    sd = sd_slope,
    CI_lower = ci_lower,
    CI_upper = ci_upper
  )
}


exp_phylum <- get_scaling_exponents(df_phylum, "Phylum")
exp_class  <- get_scaling_exponents(df_class, "Class")
exp_order  <- get_scaling_exponents(df_order, "Order")
exp_family  <- get_scaling_exponents(df_order, "Family")
exp_genus  <- get_scaling_exponents(df_order, "Genus")

slope_summary(exp_phylum)
slope_summary(exp_class)
slope_summary(exp_order)
slope_summary(exp_family)
slope_summary(exp_genus)


library(ggplot2)

exp_phylum$level <- "Phylum"
exp_class$level  <- "Class"
exp_order$level  <- "Order"
exp_family$level  <- "Family"
exp_genus$level  <- "Genus"

exp_all <- dplyr::bind_rows(exp_phylum, exp_class, exp_order, exp_family, exp_genus)

exp_all$level <- factor(
  exp_all$level,
  levels = c("Genus", "Family", "Order", "Class", "Phylum")
)
ggplot(exp_all, aes(x=level, y=slope)) +
  stat_summary(fun=mean, geom="point", size=4) +
  stat_summary(fun.data=mean_cl_normal, geom="errorbar", width=0.2) +
  geom_jitter(width=0.1, alpha=0.5) +
  geom_hline(yintercept=0.75, linetype="dashed") +
  labs(
    x="Taxonomic level",
    y="Scaling exponent (b)",
    title="Distribution of metabolic scaling exponents"
  )
#Note slope estimate are for taxa spanning 3 or more orders of magnitude

###########################################


# Install packages if needed
# install.packages("ggplot2")
# install.packages("patchwork")

library(ggplot2)
library(patchwork)

# -----------------------------
# Generate base data
M <- seq(1, 1e8, length.out = 500)
k <- 1
B0 <- 1

# -----------------------------
# Panel A: Mass-specific metabolism
df1 <- data.frame(
  M = M,
  B_over_M = B0 * M^(-1/4)
)

p1 <- ggplot(df1, aes(x = M, y = B_over_M)) +
  geom_line(linewidth = 1) +
  scale_x_log10() +
  scale_y_log10() +
  labs(
    title = "A. Mass-specific metabolism",
    x = "Body Mass (M)",
    y = "B/M"
  ) +
  theme_minimal()

# -----------------------------
# Panel B: Efficiency
df2 <- data.frame(
  M = M,
  efficiency = 1 - k * M^(-1/4)
)

p2 <- ggplot(df2, aes(x = M, y = efficiency)) +
  geom_line(linewidth = 1) +
  scale_x_log10() +
  labs(
    title = "B. Efficiency saturates",
    x = "Body Mass (M)",
    y = "e(M)"
  ) +
  theme_minimal()

# -----------------------------
# Panel C: Marginal gains
df3 <- data.frame(
  M = M,
  marginal_gain = (k/4) * M^(-5/4)
)

p3 <- ggplot(df3, aes(x = M, y = marginal_gain)) +
  geom_line(linewidth = 1) +
  scale_x_log10() +
  scale_y_log10() +
  labs(
    title = "C. Marginal gains",
    x = "Body Mass (M)",
    y = "de/dM"
  ) +
  theme_minimal()

# -----------------------------
# Panel D: Bounded normalization shifts (FIXED)

# Define shared metabolic bounds
Bmax <- 1.0   # upper bound (small organisms)
Bmin <- 0.05  # lower bound (large organisms)

# Fixed ratio of size range implied by bounds
R <- (Bmax / Bmin)^4

# Define lineage-specific minimum sizes (shift along size axis)
Mmin_values <- c(1, 1e2, 1e4)

df4 <- data.frame()

for (i in 1:length(Mmin_values)) {
  
  Mmin <- Mmin_values[i]
  Mmax <- Mmin * R
  
  # Generate size range within lineage
  M_lineage <- seq(Mmin, Mmax, length.out = 300)
  
  # Set B0 so that B/M at smallest size = Bmax
  B0_lineage <- Bmax * Mmin^(1/4)
  
  B_over_M <- B0_lineage * M_lineage^(-1/4)
  
  temp <- data.frame(
    M = M_lineage,
    B_over_M = B_over_M,
    lineage = paste0("Lineage ", i)
  )
  
  df4 <- rbind(df4, temp)
}

p4 <- ggplot(df4, aes(x = M, y = B_over_M, linetype = lineage)) +
  geom_line(linewidth = 1) +
  scale_x_log10() +
  scale_y_log10() +
  labs(
    title = "D. Lineages span bounded metabolic range",
    x = "Body Mass (M)",
    y = "B/M",
    linetype = "Lineage"
  ) +
  theme_minimal() +
  theme(legend.position = "bottom")

# -----------------------------
# Combine panels
final_plot <- (p1 | p2) / (p3 | p4)

# Add overall title
final_plot <- final_plot + plot_annotation(
  title = "Diminishing Returns and Evolutionary Constraints on Metabolic Scaling"
)

# -----------------------------
# Display
print(final_plot)

# -----------------------------
# Save
ggsave("scaling_multipanel_corrected.png",
       final_plot, width = 10, height = 8, dpi = 300)


#################
# Install packages if needed
# install.packages("ggplot2")
# install.packages("patchwork")

library(ggplot2)
library(patchwork)

# -----------------------------
# Shared metabolic bounds
Bmax <- 1.0
Bmin <- 0.05

# Implied fixed size ratio
R <- (Bmax / Bmin)^4

# Define lineages via Mmin (controls everything)
Mmin_values <- c(1, 1e2, 1e4)

df_all <- data.frame()

for (i in 1:length(Mmin_values)) {
  
  Mmin <- Mmin_values[i]
  Mmax <- Mmin * R
  
  # Generate lineage-specific size range
  M <- seq(Mmin, Mmax, length.out = 300)
  
  # B0 determined by anchoring upper bound
  B0 <- Bmax * Mmin^(1/4)
  
  # Core relationships
  B_over_M <- B0 * M^(-1/4)
  
  # Smooth bounded efficiency
  efficiency <- (Bmax - B_over_M) / (Bmax - Bmin)
  
  # Marginal gain (analytical derivative scaled)
  marginal_gain <- (B0/4) * M^(-5/4) / (Bmax - Bmin)
  
  temp <- data.frame(
    M = M,
    B_over_M = B_over_M,
    efficiency = efficiency,
    marginal_gain = marginal_gain,
    lineage = paste0("Lineage ", i),
    B0 = B0
  )
  
  df_all <- rbind(df_all, temp)
}

# -----------------------------
# Panel A: Mass-specific metabolism
p1 <- ggplot(df_all, aes(x = M, y = B_over_M, linetype = lineage)) +
  geom_line(linewidth = 1) +
  scale_x_log10() +
  scale_y_log10() +
  labs(
    title = "A. Mass-specific metabolism",
    x = "Body Mass (M)",
    y = "B/M",
    linetype = "Lineage"
  ) +
  theme_minimal() +
  theme(legend.position = "none")

# -----------------------------
# Panel B: Efficiency (smooth saturation)
p2 <- ggplot(df_all, aes(x = M, y = efficiency, linetype = lineage)) +
  geom_line(linewidth = 1) +
  scale_x_log10() +
  labs(
    title = "B. Efficiency (bounded and saturating)",
    x = "Body Mass (M)",
    y = "e(M)"
  ) +
  theme_minimal() +
  theme(legend.position = "none")

# -----------------------------
# Panel C: Marginal gains
p3 <- ggplot(df_all, aes(x = M, y = marginal_gain, linetype = lineage)) +
  geom_line(linewidth = 1) +
  scale_x_log10() +
  scale_y_log10() +
  labs(
    title = "C. Marginal gains decline",
    x = "Body Mass (M)",
    y = "de/dM"
  ) +
  theme_minimal() +
  theme(legend.position = "none")

# -----------------------------
# Panel D: Same as A but highlight B0 differences
p4 <- ggplot(df_all, aes(x = M, y = B_over_M, linetype = lineage)) +
  geom_line(linewidth = 1.2) +
  scale_x_log10() +
  scale_y_log10() +
  labs(
    title = "D. Lineage shifts (B0 increases with size)",
    x = "Body Mass (M)",
    y = "B/M",
    linetype = "Lineage"
  ) +
  theme_minimal() +
  theme(legend.position = "bottom")

# -----------------------------
# Combine panels
final_plot <- (p1 | p2) / (p3 | p4)

final_plot <- final_plot + plot_annotation(
  title = "Diminishing Returns, Bounded Metabolic Intensity, and Lineage Shifts"
)

# -----------------------------
# Display
print(final_plot)

# -----------------------------
# Save
ggsave("scaling_multipanel_final.png",
       final_plot, width = 10, height = 8, dpi = 300)


#######
# Install if needed
# install.packages("ggplot2")
# install.packages("patchwork")

library(ggplot2)
library(patchwork)

# -----------------------------
# Shared metabolic bounds
Bmax <- 1.0
Bmin <- 0.05

# Fixed size ratio
R <- (Bmax / Bmin)^4

# Define lineages via minimum size
Mmin_values <- c(1, 1e2, 1e4)

df_all <- data.frame()

for (i in 1:length(Mmin_values)) {
  
  Mmin <- Mmin_values[i]
  Mmax <- Mmin * R
  
  M <- seq(Mmin, Mmax, length.out = 300)
  
  # Normalization constant from constraint
  B0 <- Bmax * Mmin^(1/4)
  
  # Scaling relationships
  B <- B0 * M^(3/4)
  B_over_M <- B0 * M^(-1/4)
  
  # Relative efficiency (bounded)
  efficiency <- (Bmax - B_over_M) / (Bmax - Bmin)
  
  # Marginal gains
  marginal_gain <- (B0 / 4) * M^(-5/4) / (Bmax - Bmin)
  
  temp <- data.frame(
    M = M,
    B = B,
    B_over_M = B_over_M,
    efficiency = efficiency,
    marginal_gain = marginal_gain,
    lineage = paste0("Lineage ", i),
    B0 = B0
  )
  
  df_all <- rbind(df_all, temp)
}

# -----------------------------
# Legend labels (math notation)
labels_B0 <- unique(df_all[, c("lineage", "B0")])

label_map <- setNames(
  paste0("B[0] == ", signif(labels_B0$B0, 3)),
  labels_B0$lineage
)

# -----------------------------
# Okabe–Ito colorblind-safe palette
lineage_colors <- c(
  "Lineage 1" = "#0072B2",  # blue
  "Lineage 2" = "#D55E00",  # orange
  "Lineage 3" = "#009E73"   # green
)

# -----------------------------
# Panel A: B vs M
p1 <- ggplot(df_all, aes(x = M, y = B, color = lineage)) +
  geom_line(linewidth = 1.3) +
  scale_x_log10() +
  scale_y_log10() +
  scale_color_manual(
    values = lineage_colors,
    breaks = names(label_map),
    labels = parse(text = unname(label_map))
  ) +
  labs(
    title = "A. Metabolic rate scales with body mass",
    x = "Body Mass (M)",
    y = "B",
    color = expression(B[0])
  ) +
  theme_minimal() +
  theme(legend.position = "none")

# -----------------------------
# Panel B: Efficiency
p2 <- ggplot(df_all, aes(x = M, y = efficiency, color = lineage)) +
  geom_line(linewidth = 1.3) +
  scale_x_log10() +
  scale_color_manual(
    values = lineage_colors,
    breaks = names(label_map),
    labels = parse(text = unname(label_map))
  ) +
  labs(
    title = "B. Relative efficiency within bounded metabolic range",
    x = "Body Mass (M)",
    y = "Relative efficiency"
  ) +
  theme_minimal() +
  theme(legend.position = "none")

# -----------------------------
# Panel C: Marginal gains
p3 <- ggplot(df_all, aes(x = M, y = marginal_gain, color = lineage)) +
  geom_line(linewidth = 1.3) +
  scale_x_log10() +
  scale_y_log10() +
  scale_color_manual(
    values = lineage_colors,
    breaks = names(label_map),
    labels = parse(text = unname(label_map))
  ) +
  labs(
    title = "C. Marginal gains decline",
    x = "Body Mass (M)",
    y = "de/dM"
  ) +
  theme_minimal() +
  theme(legend.position = "none")

# -----------------------------
# Panel D: Bounded B/M
p4 <- ggplot(df_all, aes(x = M, y = B_over_M, color = lineage)) +
  geom_line(linewidth = 1.4) +
  scale_x_log10() +
  scale_y_log10() +
  geom_hline(yintercept = Bmax, linetype = "dashed") +
  geom_hline(yintercept = Bmin, linetype = "dashed") +
  scale_color_manual(
    values = lineage_colors,
    breaks = names(label_map),
    labels = parse(text = unname(label_map))
  ) +
  labs(
    title = "D. Bounded metabolic intensity",
    x = "Body Mass (M)",
    y = "B/M",
    color = expression(B[0])
  ) +
  theme_minimal() +
  theme(legend.position = "bottom")

# -----------------------------
# Combine panels
final_plot <- (p1 | p2) / (p3 | p4)

final_plot <- final_plot + plot_annotation(
  title = "Scaling, Saturation, and Lineage Shifts in Metabolic Organization"
)

# -----------------------------
# Display
print(final_plot)

# -----------------------------
# Save figure
ggsave("scaling_multipanel_publication.png",
       final_plot, width = 10, height = 8, dpi = 300)

### Figure X. Scaling, bounded metabolic intensity, and macroevolutionary predictions from a theory of biological organization. Panels illustrate quantitative predictions derived from a scaling framework that links body size, metabolic intensity, and evolutionary innovation. (A) Prediction 1 (shared scaling relationships). Whole-organism metabolic rate scales with body mass as B=B_0 M^(3/4). Closely related species that differ in size fall along parallel scaling relationships with a conserved exponent but lineage-specific normalization constants B_0. (B) Prediction 3 (diminishing returns and saturation). Relative efficiency within a bounded metabolic range increases with body size but saturates as mass-specific metabolism declines, B/M=B_0 M^(-1/4). This shows that gains from increasing size are finite within lineages. (C) Prediction 3 (marginal gains). The marginal gains in efficiency decline as de/dM∝M^(-5/4), demonstrating that increases in body size yield progressively smaller improvements in energetic performance. (D) Prediction 2 and 4 (bounded metabolic intensity and lineage shifts). Mass-specific metabolism is constrained between shared upper and lower bounds, (B/M)_maxand (B/M)_min, defining a bounded energetic trait space. Lineages span this space by shifting their minimum and maximum body sizes, which determines their normalization constants B_0, rather than by altering the scaling exponent. Together, these panels show that the patterns are not descriptive but emerge as explicit predictions of the theory. The framework implies that diversification within lineages proceeds along conserved scaling axes until energetic gains from size saturate, after which further evolutionary change requires shifts in metabolic normalization associated with changes in physiology, organization, and resource use. These results provide a mechanistic explanation for why scaling exponents remain invariant while normalization constants and characteristic body sizes change systematically across evolutionary lineages.


###########



##############################
# Load libraries
##############################
library(dplyr)
library(ggplot2)
library(car)

##############################
# 1. Define clade data
##############################
df <- data.frame(
  rank = 1:19,
  
  taxa = c("Unicells","Protozoa","Porifera","Anthozoa","Scyphozoa",
           "Nematoda","Mollusca","Branchiopoda","Oligochaeta",
           "Gymnolaemata","Malacostraca","Copepoda","Arachnida",
           "Insecta","Osteichthyes","Amphibia","Squamata",
           "Mammalia","Aves"),
  
  b = c(0.79,0.68,0.55,0.86,0.85,
        0.72,0.75,0.70,0.75,
        0.80,0.78,0.72,0.76,
        0.69,0.76,0.77,0.76,
        0.75,0.68),
  
  B0 = c(0.0365,0.0088,0.0247,0.0738,0.0135,
         0.0236,0.159,0.0570,0.0908,
         0.3080,0.3080,0.2115,0.0859,
         0.3655,0.2870,0.2960,0.3800,
         3.5900,3.8000),
  
  Mmin = c(1e-16,1e-12,NA,8e-11,NA,
           7.06e-11,9.1e-9,NA,2e-8,
           1e-5,7.4e-7,1.1e-8,1e-5,
           7.4e-9,2e-5,5e-4,5e-4,
           0.002,0.002),
  
  Mmax = c(4.7e-10,8e-8,NA,1e-5,NA,
           1.45e-7,250,NA,1.26e-5,
           0.1,2.8e-4,9.9e-6,0.1,
           0.1,2000,25,135,
           181400,156)
)

##############################
# 2. Compute metabolic rates
##############################
df$Bmax <- df$B0 * df$Mmax^df$b
df$Bmin <- df$B0 * df$Mmin^df$b

df$BM_max <- df$Bmax / df$Mmax   # large body limit
df$BM_min <- df$Bmin / df$Mmin   # small body limit

##############################
# 3. Estimate global bounds
##############################
BM_upper <- max(df$BM_min, na.rm=TRUE)   # (B/M)_max
BM_lower <- min(df$BM_max, na.rm=TRUE)   # (B/M)_min

BM_upper
BM_lower

##############################
# 4. Predict size limits
##############################
df$Mmin_pred <- (df$B0 / BM_upper)^4
df$Mmax_pred <- (df$B0 / BM_lower)^4

##############################
# 5. Prepare datasets
##############################
df_min <- df %>% filter(!is.na(Mmin))
df_max <- df %>% filter(!is.na(Mmax))

##############################
# 6. Test prediction: Mmin
##############################
fit_min <- lm(log10(Mmin) ~ log10(Mmin_pred), data=df_min)
summary(fit_min)

plot(df_min$Mmin_pred, df_min$Mmin,
     log="xy",
     pch=19,
     xlab="Predicted Mmin",
     ylab="Observed Mmin",
     main="Test of minimum size prediction")

abline(0,1,col="red",lwd=2)
abline(fit_min, col="black", lwd=2)

##############################
# 7. Test prediction: Mmax
##############################
fit_max <- lm(log10(Mmax) ~ log10(Mmax_pred), data=df_max)
summary(fit_max)

plot(df_max$Mmax_pred, df_max$Mmax,
     log="xy",
     pch=19,
     xlab="Predicted Mmax",
     ylab="Observed Mmax",
     main="Test of maximum size prediction")

abline(0,1,col="red",lwd=2)
abline(fit_max, col="black", lwd=2)

##############################
# 8. Test slope = 1 (strict prediction)
##############################
linearHypothesis(fit_min, "log10(Mmin_pred) = 1")
linearHypothesis(fit_max, "log10(Mmax_pred) = 1")

##############################
# 9. Test scaling with B0
##############################
fit_Mmin_B0 <- lm(log10(Mmin) ~ log10(B0), data=df_min)
fit_Mmax_B0 <- lm(log10(Mmax) ~ log10(B0), data=df_max)

summary(fit_Mmin_B0)
summary(fit_Mmax_B0)

# Plot Mmin vs B0
plot(df_min$B0, df_min$Mmin,
     log="xy",
     pch=19,
     xlab="B0",
     ylab="Mmin",
     main="Scaling of minimum size")

abline(fit_Mmin_B0, lwd=2)
abline(a=coef(fit_Mmin_B0)[1], b=4, col="red", lty=2)

# Plot Mmax vs B0
plot(df_max$B0, df_max$Mmax,
     log="xy",
     pch=19,
     xlab="B0",
     ylab="Mmax",
     main="Scaling of maximum size")

abline(fit_Mmax_B0, lwd=2)
abline(a=coef(fit_Mmax_B0)[1], b=4, col="red", lty=2)

##############################
# 10. Test constant size breadth
##############################
df$size_ratio <- df$Mmax / df$Mmin

summary(df$size_ratio)

plot(df$B0, df$size_ratio,
     log="xy",
     pch=19,
     xlab="B0",
     ylab="Mmax / Mmin",
     main="Test of constant size breadth")

fit_ratio <- lm(log10(size_ratio) ~ log10(B0), data=df)
summary(fit_ratio)

##############################
# 11. Optional: visualize prediction collapse
##############################
ggplot(df_min, aes(Mmin_pred, Mmin)) +
  geom_point() +
  scale_x_log10() +
  scale_y_log10() +
  geom_abline(slope=1, intercept=0, linetype="dashed") +
  labs(title="Minimum size prediction",
       x="Predicted",
       y="Observed")

ggplot(df_max, aes(Mmax_pred, Mmax)) +
  geom_point() +
  scale_x_log10() +
  scale_y_log10() +
  geom_abline(slope=1, intercept=0, linetype="dashed") +
  labs(title="Maximum size prediction",
       x="Predicted",
       y="Observed")





#############################






############################################################
# Load libraries
############################################################
library(dplyr)
library(readr)
library(ggplot2)
library(car)

############################################################
# 1. LOAD HOEHLER DATA (ENERGETIC BOUNDS)
############################################################

file_path <- "/Users/brianjenquist/Desktop/Hoehler_etal_PNAS_MetabolicRateData_For_R.csv"

df_met <- read_csv(file_path)

df_met <- df_met %>%
  mutate(
    mass_g = Dry_Mass_g,
    metabolic_rate = Metabolic_Rate_W_at_25_C,
    mass_specific = metabolic_rate / mass_g,
    log_mass = log10(mass_g),
    log_ms = log10(mass_specific)
  ) %>%
  filter(is.finite(log_mass), is.finite(log_ms))

############################################################
# 2. ESTIMATE ENVELOPE (BOUNDED METABOLIC SPACE)
############################################################

# Bin data across log-mass
df_bins <- df_met %>%
  mutate(size_bin = cut(log_mass, breaks = 25))

# Compute upper and lower envelope
envelope <- df_bins %>%
  group_by(size_bin) %>%
  summarise(
    mass = 10^(mean(log_mass, na.rm=TRUE)),
    ms_max = max(mass_specific, na.rm=TRUE),
    ms_min = min(mass_specific, na.rm=TRUE),
    .groups="drop"
  )

############################################################
# 3. ESTIMATE GLOBAL BOUNDS (ROBUST)
############################################################

BM_upper <- quantile(envelope$ms_max, 0.95, na.rm=TRUE)
BM_lower <- quantile(envelope$ms_min, 0.05, na.rm=TRUE)

cat("Estimated upper bound (B/M)_max:", BM_upper, "\n")
cat("Estimated lower bound (B/M)_min:", BM_lower, "\n")

############################################################
# 4. LOAD CLADE DATA (INDEPENDENT TEST SET)
############################################################

df_clade <- data.frame(
  rank = 1:19,
  taxa = c("Unicells","Protozoa","Porifera","Anthozoa","Scyphozoa",
           "Nematoda","Mollusca","Branchiopoda","Oligochaeta",
           "Gymnolaemata","Malacostraca","Copepoda","Arachnida",
           "Insecta","Osteichthyes","Amphibia","Squamata",
           "Mammalia","Aves"),
  
  b = c(0.79,0.68,0.55,0.86,0.85,
        0.72,0.75,0.70,0.75,
        0.80,0.78,0.72,0.76,
        0.69,0.76,0.77,0.76,
        0.75,0.68),
  
  B0 = c(0.0365,0.0088,0.0247,0.0738,0.0135,
         0.0236,0.159,0.0570,0.0908,
         0.3080,0.3080,0.2115,0.0859,
         0.3655,0.2870,0.2960,0.3800,
         3.5900,3.8000),
  
  Mmin = c(1e-16,1e-12,NA,8e-11,NA,
           7.06e-11,9.1e-9,NA,2e-8,
           1e-5,7.4e-7,1.1e-8,1e-5,
           7.4e-9,2e-5,5e-4,5e-4,
           0.002,0.002),
  
  Mmax = c(4.7e-10,8e-8,NA,1e-5,NA,
           1.45e-7,250,NA,1.26e-5,
           0.1,2.8e-4,9.9e-6,0.1,
           0.1,2000,25,135,
           181400,156)
)

############################################################
# 5. PREDICT SIZE LIMITS (NO FITTING)
############################################################

df_clade <- df_clade %>%
  mutate(
    Mmin_pred = (B0 / BM_upper)^4,
    Mmax_pred = (B0 / BM_lower)^4
  )

############################################################
# 6. TEST PREDICTIONS: MIN SIZE
############################################################

df_min <- df_clade %>% filter(!is.na(Mmin))

fit_min <- lm(log10(Mmin) ~ log10(Mmin_pred), data=df_min)
summary(fit_min)

plot(df_min$Mmin_pred, df_min$Mmin,
     log="xy",
     pch=19,
     xlab="Predicted Mmin",
     ylab="Observed Mmin",
     main="Out-of-sample test: minimum size")

abline(0,1,col="red",lwd=2)
abline(fit_min, col="black", lwd=2)

############################################################
# 7. TEST PREDICTIONS: MAX SIZE
############################################################

df_max <- df_clade %>% filter(!is.na(Mmax))

fit_max <- lm(log10(Mmax) ~ log10(Mmax_pred), data=df_max)
summary(fit_max)

plot(df_max$Mmax_pred, df_max$Mmax,
     log="xy",
     pch=19,
     xlab="Predicted Mmax",
     ylab="Observed Mmax",
     main="Out-of-sample test: maximum size")

abline(0,1,col="red",lwd=2)
abline(fit_max, col="black", lwd=2)

############################################################
# 8. TEST SLOPE = 1 (STRICT TEST)
############################################################

linearHypothesis(fit_min, "log10(Mmin_pred) = 1")
linearHypothesis(fit_max, "log10(Mmax_pred) = 1")

############################################################
# 9. TEST SCALING WITH B0
############################################################

fit_Mmin_B0 <- lm(log10(Mmin_pred) ~ log10(B0), data=df_clade)
fit_Mmax_B0 <- lm(log10(Mmax_pred) ~ log10(B0), data=df_clade)

cat("Slope Mmin vs B0:", coef(fit_Mmin_B0)[2], "\n")
cat("Slope Mmax vs B0:", coef(fit_Mmax_B0)[2], "\n")

############################################################
# 10. TEST SIZE RANGE INVARIANCE
############################################################

df_clade <- df_clade %>%
  mutate(size_ratio = Mmax / Mmin)

summary(df_clade$size_ratio)

plot(df_clade$B0, df_clade$size_ratio,
     log="xy",
     pch=19,
     xlab="B0",
     ylab="Mmax / Mmin",
     main="Test of constant size breadth")

fit_ratio <- lm(log10(size_ratio) ~ log10(B0), data=df_clade)
summary(fit_ratio)

############################################################
# 11. VISUALIZE EMPIRICAL ENVELOPE
############################################################

ggplot(df_met, aes(x = mass_g, y = mass_specific)) +
  geom_point(alpha=0.1) +
  geom_line(data=envelope, aes(x = mass, y = ms_max), color="red", linewidth=1) +
  geom_line(data=envelope, aes(x = mass, y = ms_min), color="blue", linewidth=1) +
  scale_x_log10() +
  scale_y_log10() +
  labs(
    title="Empirical bounds on mass-specific metabolism",
    x="Body mass (g)",
    y="Mass-specific metabolism (B/M)"
  ) +
  theme_minimal()





####################



############################################################
# Load libraries
############################################################
library(dplyr)
library(readr)
library(ggplot2)
library(car)

############################################################
# Helper function: slope + 95% CI label
############################################################
get_fit_label <- function(fit) {
  slope <- coef(fit)[2]
  ci <- confint(fit)[2, ]
  sprintf("slope = %.2f (95%% CI: %.2f–%.2f)", slope, ci[1], ci[2])
}

############################################################
# 1. LOAD HOEHLER DATA (ENERGETIC BOUNDS)
############################################################
file_path <- "/Users/brianjenquist/Desktop/Hoehler_etal_PNAS_MetabolicRateData_For_R.csv"

df_met <- read_csv(file_path)

df_met <- df_met %>%
  mutate(
    mass_g = Dry_Mass_g,
    metabolic_rate = Metabolic_Rate_W_at_25_C,
    mass_specific = metabolic_rate / mass_g,
    log_mass = log10(mass_g),
    log_ms = log10(mass_specific)
  ) %>%
  filter(is.finite(log_mass), is.finite(log_ms))

############################################################
# 2. ESTIMATE ENERGETIC BOUNDS
############################################################
df_bins <- df_met %>%
  mutate(size_bin = cut(log_mass, breaks = 25))

envelope <- df_bins %>%
  group_by(size_bin) %>%
  summarise(
    mass = 10^(mean(log_mass, na.rm=TRUE)),
    ms_max = max(mass_specific, na.rm=TRUE),
    ms_min = min(mass_specific, na.rm=TRUE),
    .groups="drop"
  )

BM_upper <- quantile(envelope$ms_max, 0.95, na.rm=TRUE)
BM_lower <- quantile(envelope$ms_min, 0.05, na.rm=TRUE)

############################################################
# 3. CLADE DATA
############################################################
df_clade <- data.frame(
  rank = 1:19,
  taxa = c("Unicells","Protozoa","Porifera","Anthozoa","Scyphozoa",
           "Nematoda","Mollusca","Branchiopoda","Oligochaeta",
           "Gymnolaemata","Malacostraca","Copepoda","Arachnida",
           "Insecta","Osteichthyes","Amphibia","Squamata",
           "Mammalia","Aves"),
  
  b = c(0.79,0.68,0.55,0.86,0.85,
        0.72,0.75,0.70,0.75,
        0.80,0.78,0.72,0.76,
        0.69,0.76,0.77,0.76,
        0.75,0.68),
  
  B0 = c(0.0365,0.0088,0.0247,0.0738,0.0135,
         0.0236,0.159,0.0570,0.0908,
         0.3080,0.3080,0.2115,0.0859,
         0.3655,0.2870,0.2960,0.3800,
         3.5900,3.8000),
  
  Mmin = c(1e-16,1e-12,NA,8e-11,NA,
           7.06e-11,9.1e-9,NA,2e-8,
           1e-5,7.4e-7,1.1e-8,1e-5,
           7.4e-9,2e-5,5e-4,5e-4,
           0.002,0.002),
  
  Mmax = c(4.7e-10,8e-8,NA,1e-5,NA,
           1.45e-7,250,NA,1.26e-5,
           0.1,2.8e-4,9.9e-6,0.1,
           0.1,2000,25,135,
           181400,156)
)

############################################################
# 4. PREDICTIONS (NO FITTING)
############################################################
df_clade <- df_clade %>%
  mutate(
    Mmin_pred = (B0 / BM_upper)^4,
    Mmax_pred = (B0 / BM_lower)^4
  )

df_min <- df_clade %>% filter(!is.na(Mmin))
df_max <- df_clade %>% filter(!is.na(Mmax))

############################################################
# 5. FIT MODELS
############################################################
fit_min <- lm(log10(Mmin) ~ log10(Mmin_pred), data=df_min)
fit_max <- lm(log10(Mmax) ~ log10(Mmax_pred), data=df_max)

fit_scaling_min <- lm(log10(Mmin) ~ log10(B0), data=df_min)
fit_scaling_max <- lm(log10(Mmax) ~ log10(B0), data=df_max)

############################################################
# 6. PLOT 1 — PREDICTED vs OBSERVED
############################################################
p1 <- ggplot(df_min, aes(Mmin_pred, Mmin)) +
  geom_point(size=2) +
  scale_x_log10() +
  scale_y_log10() +
  geom_abline(slope=1, intercept=0, linetype="dashed", color="red") +
  geom_smooth(method="lm", se=FALSE, color="black") +
  annotate("text",
           x=min(df_min$Mmin_pred),
           y=max(df_min$Mmin),
           label=get_fit_label(fit_min),
           hjust=0, vjust=1) +
  labs(title="A. Minimum size prediction",
       x="Predicted Mmin",
       y="Observed Mmin") +
  theme_minimal()

p2 <- ggplot(df_max, aes(Mmax_pred, Mmax)) +
  geom_point(size=2) +
  scale_x_log10() +
  scale_y_log10() +
  geom_abline(slope=1, intercept=0, linetype="dashed", color="red") +
  geom_smooth(method="lm", se=FALSE, color="black") +
  annotate("text",
           x=min(df_max$Mmax_pred),
           y=max(df_max$Mmax),
           label=get_fit_label(fit_max),
           hjust=0, vjust=1) +
  labs(title="B. Maximum size prediction",
       x="Predicted Mmax",
       y="Observed Mmax") +
  theme_minimal()

############################################################
# 7. PLOT 2 — SCALING TEST (M ∝ B0^4)
############################################################
p3 <- ggplot(df_min, aes(B0, Mmin)) +
  geom_point(size=2) +
  scale_x_log10() +
  scale_y_log10() +
  geom_smooth(method="lm", se=FALSE) +
  annotate("text",
           x=min(df_min$B0),
           y=max(df_min$Mmin),
           label=get_fit_label(fit_scaling_min),
           hjust=0, vjust=1) +
  labs(title=expression("C. Scaling: " ~ M[min] ~ propto ~ B[0]^4),
       x=expression(B[0]),
       y=expression(M[min])) +
  theme_minimal()

############################################################
# 8. PLOT 3 — RESIDUAL TEST
############################################################
df_min$residuals <- resid(fit_min)

p4 <- ggplot(df_min, aes(Mmin_pred, residuals)) +
  geom_point(size=2) +
  scale_x_log10() +
  geom_hline(yintercept=0, linetype="dashed") +
  labs(title="D. Residual structure",
       x="Predicted Mmin",
       y="Residuals") +
  theme_minimal()

############################################################
# 9. COMBINE PANELS
############################################################
library(patchwork)

final_plot <- (p1 | p2) / (p3 | p4)

print(final_plot)

############################################################
# 10. OPTIONAL: SAVE FIGURE
############################################################
ggsave("bounded_scaling_tests.png",
       final_plot,
       width=10,
       height=8,
       dpi=300)



##########################
##########################




############################################################
# Load libraries
############################################################
library(dplyr)
library(readr)
library(ggplot2)
library(car)
library(patchwork)

############################################################
# Helper function: slope + 95% CI label
############################################################
get_fit_label <- function(fit) {
  slope <- coef(fit)[2]
  ci <- confint(fit)[2, ]
  sprintf("slope = %.2f (95%% CI: %.2f–%.2f)", slope, ci[1], ci[2])
}

############################################################
# 1. LOAD HOEHLER DATA (ENERGETIC BOUNDS)
############################################################
file_path <- "/Users/brianjenquist/Desktop/Hoehler_etal_PNAS_MetabolicRateData_For_R.csv"

df_met <- read_csv(file_path)

df_met <- df_met %>%
  mutate(
    mass_g = Dry_Mass_g,
    metabolic_rate = Metabolic_Rate_W_at_25_C,
    mass_specific = metabolic_rate / mass_g,
    log_mass = log10(mass_g),
    log_ms = log10(mass_specific)
  ) %>%
  filter(is.finite(log_mass), is.finite(log_ms))

############################################################
# 2. ESTIMATE ENERGETIC BOUNDS
############################################################
df_bins <- df_met %>%
  mutate(size_bin = cut(log_mass, breaks = 25))

envelope <- df_bins %>%
  group_by(size_bin) %>%
  summarise(
    mass = 10^(mean(log_mass, na.rm=TRUE)),
    ms_max = max(mass_specific, na.rm=TRUE),
    ms_min = min(mass_specific, na.rm=TRUE),
    .groups="drop"
  )

BM_upper <- quantile(envelope$ms_max, 0.95, na.rm=TRUE)
BM_lower <- quantile(envelope$ms_min, 0.05, na.rm=TRUE)

############################################################
# 3. CLADE DATA
############################################################
df_clade <- data.frame(
  rank = 1:19,
  taxa = c("Unicells","Protozoa","Porifera","Anthozoa","Scyphozoa",
           "Nematoda","Mollusca","Branchiopoda","Oligochaeta",
           "Gymnolaemata","Malacostraca","Copepoda","Arachnida",
           "Insecta","Osteichthyes","Amphibia","Squamata",
           "Mammalia","Aves"),
  
  b = c(0.79,0.68,0.55,0.86,0.85,
        0.72,0.75,0.70,0.75,
        0.80,0.78,0.72,0.76,
        0.69,0.76,0.77,0.76,
        0.75,0.68),
  
  B0 = c(0.0365,0.0088,0.0247,0.0738,0.0135,
         0.0236,0.159,0.0570,0.0908,
         0.3080,0.3080,0.2115,0.0859,
         0.3655,0.2870,0.2960,0.3800,
         3.5900,3.8000),
  
  Mmin = c(1e-16,1e-12,NA,8e-11,NA,
           7.06e-11,9.1e-9,NA,2e-8,
           1e-5,7.4e-7,1.1e-8,1e-5,
           7.4e-9,2e-5,5e-4,5e-4,
           0.002,0.002),
  
  Mmax = c(4.7e-10,8e-8,NA,1e-5,NA,
           1.45e-7,250,NA,1.26e-5,
           0.1,2.8e-4,9.9e-6,0.1,
           0.1,2000,25,135,
           181400,156)
)

############################################################
# 4. PREDICTIONS (NO FITTING)
############################################################
df_clade <- df_clade %>%
  mutate(
    Mmin_pred = (B0 / BM_upper)^4,
    Mmax_pred = (B0 / BM_lower)^4
  )

df_min <- df_clade %>% filter(!is.na(Mmin))
df_max <- df_clade %>% filter(!is.na(Mmax))

############################################################
# 5. FIT MODELS
############################################################
fit_min <- lm(log10(Mmin) ~ log10(Mmin_pred), data=df_min)
fit_max <- lm(log10(Mmax) ~ log10(Mmax_pred), data=df_max)
fit_scaling_min <- lm(log10(Mmin) ~ log10(B0), data=df_min)

############################################################
# 6. PANEL A — MIN SIZE
############################################################
p1 <- ggplot(df_min, aes(Mmin_pred, Mmin)) +
  geom_point(size=2) +
  scale_x_log10() +
  scale_y_log10() +
  geom_abline(slope=1, intercept=0, linetype="dashed", color="red") +
  geom_smooth(method="lm", se=FALSE, color="black") +
  annotate("text",
           x=min(df_min$Mmin_pred),
           y=max(df_min$Mmin),
           label=get_fit_label(fit_min),
           hjust=0, vjust=1) +
  labs(title="A. Minimum size prediction",
       x="Predicted Mmin",
       y="Observed Mmin") +
  theme_minimal()

############################################################
# 7. PANEL B — MAX SIZE
############################################################
p2 <- ggplot(df_max, aes(Mmax_pred, Mmax)) +
  geom_point(size=2) +
  scale_x_log10() +
  scale_y_log10() +
  geom_abline(slope=1, intercept=0, linetype="dashed", color="red") +
  geom_smooth(method="lm", se=FALSE, color="black") +
  annotate("text",
           x=min(df_max$Mmax_pred),
           y=max(df_max$Mmax),
           label=get_fit_label(fit_max),
           hjust=0, vjust=1) +
  labs(title="B. Maximum size prediction",
       x="Predicted Mmax",
       y="Observed Mmax") +
  theme_minimal()

############################################################
# 8. PANEL C — SCALING TEST
############################################################
p3 <- ggplot(df_min, aes(B0, Mmin)) +
  geom_point(size=2) +
  scale_x_log10() +
  scale_y_log10() +
  geom_smooth(method="lm", se=FALSE) +
  annotate("text",
           x=min(df_min$B0),
           y=max(df_min$Mmin),
           label=get_fit_label(fit_scaling_min),
           hjust=0, vjust=1) +
  labs(title=expression("C. Scaling: " ~ M[min] ~ propto ~ B[0]^4),
       x=expression(B[0]),
       y=expression(M[min])) +
  theme_minimal()

############################################################
# 9. PANEL D — SIZE BREADTH (NEW)
############################################################
df_ratio <- df_clade %>%
  filter(!is.na(Mmin), !is.na(Mmax)) %>%
  mutate(size_ratio = Mmax / Mmin)

fit_ratio <- lm(log10(size_ratio) ~ log10(B0), data=df_ratio)

ratio_ref <- 10^(mean(log10(df_ratio$size_ratio), na.rm=TRUE))

p4 <- ggplot(df_ratio, aes(B0, size_ratio)) +
  geom_point(size=2) +
  scale_x_log10() +
  scale_y_log10() +
  geom_hline(yintercept = ratio_ref, linetype="dashed", color="red") +
  geom_smooth(method="lm", se=FALSE, color="black") +
  annotate("text",
           x=min(df_ratio$B0),
           y=max(df_ratio$size_ratio),
           label=get_fit_label(fit_ratio),
           hjust=0, vjust=1) +
  labs(title=expression("D. Size breadth: " ~ M[max]/M[min] ~ "vs." ~ B[0]),
       x=expression(B[0]),
       y=expression(M[max]/M[min])) +
  theme_minimal()

############################################################
# 10. COMBINE PANELS
############################################################
final_plot <- (p1 | p2) / (p3 | p4)

print(final_plot)

############################################################
# 11. SAVE FIGURE
############################################################
ggsave("bounded_scaling_tests.png",
       final_plot,
       width=10,
       height=8,
       dpi=300)






######################


############################################################
# Load libraries
############################################################
library(dplyr)
library(readr)
library(ggplot2)
library(car)
library(patchwork)

############################################################
# Helper function: slope + 95% CI label
############################################################
get_fit_label <- function(fit) {
  slope <- coef(fit)[2]
  ci <- confint(fit)[2, ]
  sprintf("slope = %.2f (95%% CI: %.2f–%.2f)", slope, ci[1], ci[2])
}

############################################################
# 1. LOAD HOEHLER DATA (ENERGETIC BOUNDS)
############################################################
file_path <- "/Users/brianjenquist/Desktop/Hoehler_etal_PNAS_MetabolicRateData_For_R.csv"

df_met <- read_csv(file_path)

df_met <- df_met %>%
  mutate(
    mass_g = Dry_Mass_g,
    metabolic_rate = Metabolic_Rate_W_at_25_C,
    mass_specific = metabolic_rate / mass_g,
    log_mass = log10(mass_g),
    log_ms = log10(mass_specific)
  ) %>%
  filter(is.finite(log_mass), is.finite(log_ms))

############################################################
# 2. ESTIMATE ENERGETIC BOUNDS
############################################################
df_bins <- df_met %>%
  mutate(size_bin = cut(log_mass, breaks = 25))

envelope <- df_bins %>%
  group_by(size_bin) %>%
  summarise(
    mass = 10^(mean(log_mass, na.rm=TRUE)),
    ms_max = max(mass_specific, na.rm=TRUE),
    ms_min = min(mass_specific, na.rm=TRUE),
    .groups="drop"
  )

BM_upper <- quantile(envelope$ms_max, 0.95, na.rm=TRUE)
BM_lower <- quantile(envelope$ms_min, 0.05, na.rm=TRUE)

############################################################
# 3. CLADE DATA
############################################################
df_clade <- data.frame(
  rank = 1:19,
  taxa = c("Unicells","Protozoa","Porifera","Anthozoa","Scyphozoa",
           "Nematoda","Mollusca","Branchiopoda","Oligochaeta",
           "Gymnolaemata","Malacostraca","Copepoda","Arachnida",
           "Insecta","Osteichthyes","Amphibia","Squamata",
           "Mammalia","Aves"),
  
  b = c(0.79,0.68,0.55,0.86,0.85,
        0.72,0.75,0.70,0.75,
        0.80,0.78,0.72,0.76,
        0.69,0.76,0.77,0.76,
        0.75,0.68),
  
  B0 = c(0.0365,0.0088,0.0247,0.0738,0.0135,
         0.0236,0.159,0.0570,0.0908,
         0.3080,0.3080,0.2115,0.0859,
         0.3655,0.2870,0.2960,0.3800,
         3.5900,3.8000),
  
  Mmin = c(1e-16,1e-12,NA,8e-11,NA,
           7.06e-11,9.1e-9,NA,2e-8,
           1e-5,7.4e-7,1.1e-8,1e-5,
           7.4e-9,2e-5,5e-4,5e-4,
           0.002,0.002),
  
  Mmax = c(4.7e-10,8e-8,NA,1e-5,NA,
           1.45e-7,250,NA,1.26e-5,
           0.1,2.8e-4,9.9e-6,0.1,
           0.1,2000,25,135,
           181400,156)
)

############################################################
# 4. PREDICTIONS
############################################################
df_clade <- df_clade %>%
  mutate(
    Mmin_pred = (B0 / BM_upper)^4,
    Mmax_pred = (B0 / BM_lower)^4
  )

df_min <- df_clade %>% filter(!is.na(Mmin))
df_max <- df_clade %>% filter(!is.na(Mmax))

############################################################
# 5. FIT MODELS
############################################################
fit_min <- lm(log10(Mmin) ~ log10(Mmin_pred), data=df_min)
fit_max <- lm(log10(Mmax) ~ log10(Mmax_pred), data=df_max)

fit_scaling_min <- lm(log10(Mmin) ~ log10(B0), data=df_min)
fit_ratio <- lm(log10(Mmax/Mmin) ~ log10(B0), data=df_clade)

fit_B0_Mmax <- lm(log10(B0) ~ log10(Mmax), data=df_max)

############################################################
# PANEL A — MIN SIZE
############################################################
p1 <- ggplot(df_min, aes(Mmin_pred, Mmin)) +
  geom_point(size=2) +
  scale_x_log10() +
  scale_y_log10() +
  geom_abline(slope=1, intercept=0, linetype="dashed", color="red") +
  geom_smooth(method="lm", se=FALSE, color="black") +
  annotate("text",
           x=min(df_min$Mmin_pred),
           y=max(df_min$Mmin),
           label=get_fit_label(fit_min),
           hjust=0, vjust=1) +
  labs(title="A. Minimum size prediction",
       x="Predicted Mmin",
       y="Observed Mmin") +
  theme_minimal()

############################################################
# PANEL B — MAX SIZE
############################################################
p2 <- ggplot(df_max, aes(Mmax_pred, Mmax)) +
  geom_point(size=2) +
  scale_x_log10() +
  scale_y_log10() +
  geom_abline(slope=1, intercept=0, linetype="dashed", color="red") +
  geom_smooth(method="lm", se=FALSE, color="black") +
  annotate("text",
           x=min(df_max$Mmax_pred),
           y=max(df_max$Mmax),
           label=get_fit_label(fit_max),
           hjust=0, vjust=1) +
  labs(title="B. Maximum size prediction",
       x="Predicted Mmax",
       y="Observed Mmax") +
  theme_minimal()

############################################################
# PANEL C — SCALING (M ∝ B0^4)
############################################################
p3 <- ggplot(df_min, aes(B0, Mmin)) +
  geom_point(size=2) +
  scale_x_log10() +
  scale_y_log10() +
  geom_smooth(method="lm", se=FALSE) +
  annotate("text",
           x=min(df_min$B0),
           y=max(df_min$Mmin),
           label=get_fit_label(fit_scaling_min),
           hjust=0, vjust=1) +
  labs(title=expression("C. Scaling: " ~ M[min] ~ propto ~ B[0]^4),
       x=expression(B[0]),
       y=expression(M[min])) +
  theme_minimal()

############################################################
# PANEL D — SIZE BREADTH
############################################################
df_ratio <- df_clade %>%
  filter(!is.na(Mmin), !is.na(Mmax)) %>%
  mutate(size_ratio = Mmax / Mmin)

ratio_ref <- 10^(mean(log10(df_ratio$size_ratio)))

p4 <- ggplot(df_ratio, aes(B0, size_ratio)) +
  geom_point(size=2) +
  scale_x_log10() +
  scale_y_log10() +
  geom_hline(yintercept=ratio_ref, linetype="dashed", color="red") +
  geom_smooth(method="lm", se=FALSE, color="black") +
  annotate("text",
           x=min(df_ratio$B0),
           y=max(df_ratio$size_ratio),
           label=get_fit_label(fit_ratio),
           hjust=0, vjust=1) +
  labs(title=expression("D. Size breadth: " ~ M[max]/M[min] ~ "vs." ~ B[0]),
       x=expression(B[0]),
       y=expression(M[max]/M[min])) +
  theme_minimal()

############################################################
# PANEL E — B0 vs Mmax (slope = 1/4)
############################################################
ref_intercept <- mean(log10(df_max$B0) - 0.25 * log10(df_max$Mmax))

p5 <- ggplot(df_max, aes(Mmax, B0)) +
  geom_point(size=2) +
  scale_x_log10() +
  scale_y_log10() +
  geom_smooth(method="lm", se=FALSE, color="black") +
  geom_abline(slope=0.25, intercept=ref_intercept,
              linetype="dashed", color="red") +
  annotate("text",
           x=min(df_max$Mmax),
           y=max(df_max$B0),
           label=get_fit_label(fit_B0_Mmax),
           hjust=0, vjust=1) +
  labs(title=expression("E. Scaling: " ~ B[0] ~ propto ~ M[max]^{1/4}),
       x=expression(M[max]),
       y=expression(B[0])) +
  theme_minimal()

############################################################
# COMBINE PANELS
############################################################
final_plot <- (p1 | p2) / (p3 | p4) / p5

print(final_plot)

############################################################
# SAVE FIGURE
############################################################
ggsave("bounded_scaling_full_test.png",
       final_plot,
       width=10,
       height=12,
       dpi=300)


##############################
##############################





############################################################
# Load libraries
############################################################
library(dplyr)
library(readr)
library(ggplot2)
library(car)
library(patchwork)

############################################################
# Helper: slope + 95% CI
############################################################
get_fit_label <- function(fit) {
  slope <- coef(fit)[2]
  ci <- confint(fit)[2, ]
  sprintf("slope = %.2f (95%% CI: %.2f–%.2f)", slope, ci[1], ci[2])
}

############################################################
# 1. LOAD HOEHLER DATA
############################################################
file_path <- "/Users/brianjenquist/Desktop/Hoehler_etal_PNAS_MetabolicRateData_For_R.csv"

df_met <- read_csv(file_path)

df_met <- df_met %>%
  mutate(
    mass_g = Dry_Mass_g,
    metabolic_rate = Metabolic_Rate_W_at_25_C,
    mass_specific = metabolic_rate / mass_g,
    log_mass = log10(mass_g),
    log_ms = log10(mass_specific)
  ) %>%
  filter(is.finite(log_mass), is.finite(log_ms))

############################################################
# 2. ESTIMATE ENERGETIC BOUNDS
############################################################
df_bins <- df_met %>%
  mutate(size_bin = cut(log_mass, breaks = 25))

envelope <- df_bins %>%
  group_by(size_bin) %>%
  summarise(
    mass = 10^(mean(log_mass, na.rm=TRUE)),
    ms_max = max(mass_specific, na.rm=TRUE),
    ms_min = min(mass_specific, na.rm=TRUE),
    .groups="drop"
  )

BM_upper <- quantile(envelope$ms_max, 0.95, na.rm=TRUE)
BM_lower <- quantile(envelope$ms_min, 0.05, na.rm=TRUE)

############################################################
# 3. CLADE DATA
############################################################
df_clade <- data.frame(
  rank = 1:19,
  taxa = c("Unicells","Protozoa","Porifera","Anthozoa","Scyphozoa",
           "Nematoda","Mollusca","Branchiopoda","Oligochaeta",
           "Gymnolaemata","Malacostraca","Copepoda","Arachnida",
           "Insecta","Osteichthyes","Amphibia","Squamata",
           "Mammalia","Aves"),
  
  b = c(0.79,0.68,0.55,0.86,0.85,
        0.72,0.75,0.70,0.75,
        0.80,0.78,0.72,0.76,
        0.69,0.76,0.77,0.76,
        0.75,0.68),
  
  B0 = c(0.0365,0.0088,0.0247,0.0738,0.0135,
         0.0236,0.159,0.0570,0.0908,
         0.3080,0.3080,0.2115,0.0859,
         0.3655,0.2870,0.2960,0.3800,
         3.5900,3.8000),
  
  Mmin = c(1e-16,1e-12,NA,8e-11,NA,
           7.06e-11,9.1e-9,NA,2e-8,
           1e-5,7.4e-7,1.1e-8,1e-5,
           7.4e-9,2e-5,5e-4,5e-4,
           0.002,0.002),
  
  Mmax = c(4.7e-10,8e-8,NA,1e-5,NA,
           1.45e-7,250,NA,1.26e-5,
           0.1,2.8e-4,9.9e-6,0.1,
           0.1,2000,25,135,
           181400,156)
)

############################################################
# 4. PREDICTIONS
############################################################
df_clade <- df_clade %>%
  mutate(
    Mmin_pred = (B0 / BM_upper)^4,
    Mmax_pred = (B0 / BM_lower)^4
  )

df_min <- df_clade %>% filter(!is.na(Mmin))
df_max <- df_clade %>% filter(!is.na(Mmax))

############################################################
# 5. FIT MODELS
############################################################
fit_min <- lm(log10(Mmin) ~ log10(Mmin_pred), data=df_min)
fit_max <- lm(log10(Mmax) ~ log10(Mmax_pred), data=df_max)

fit_scaling_min <- lm(log10(Mmin) ~ log10(B0), data=df_min)
fit_ratio <- lm(log10(Mmax/Mmin) ~ log10(B0), data=df_clade)

fit_B0_Mmax <- lm(log10(B0) ~ log10(Mmax), data=df_max)
fit_B0_Mmin <- lm(log10(B0) ~ log10(Mmin), data=df_min)

############################################################
# PANEL A — MIN SIZE
############################################################
p1 <- ggplot(df_min, aes(Mmin_pred, Mmin)) +
  geom_point(size=2) +
  scale_x_log10() +
  scale_y_log10() +
  geom_abline(slope=1, intercept=0, linetype="dashed", color="red") +
  geom_smooth(method="lm", se=FALSE) +
  annotate("text",
           x=min(df_min$Mmin_pred),
           y=max(df_min$Mmin),
           label=get_fit_label(fit_min),
           hjust=0, vjust=1) +
  labs(title="A. Minimum size prediction",
       x="Predicted Mmin",
       y="Observed Mmin") +
  theme_minimal()

############################################################
# PANEL B — MAX SIZE
############################################################
p2 <- ggplot(df_max, aes(Mmax_pred, Mmax)) +
  geom_point(size=2) +
  scale_x_log10() +
  scale_y_log10() +
  geom_abline(slope=1, intercept=0, linetype="dashed", color="red") +
  geom_smooth(method="lm", se=FALSE) +
  annotate("text",
           x=min(df_max$Mmax_pred),
           y=max(df_max$Mmax),
           label=get_fit_label(fit_max),
           hjust=0, vjust=1) +
  labs(title="B. Maximum size prediction",
       x="Predicted Mmax",
       y="Observed Mmax") +
  theme_minimal()

############################################################
# PANEL C — SCALING
############################################################
p3 <- ggplot(df_min, aes(B0, Mmin)) +
  geom_point(size=2) +
  scale_x_log10() +
  scale_y_log10() +
  geom_smooth(method="lm", se=FALSE) +
  annotate("text",
           x=min(df_min$B0),
           y=max(df_min$Mmin),
           label=get_fit_label(fit_scaling_min),
           hjust=0, vjust=1) +
  labs(title=expression("C. Scaling: " ~ M[min] ~ "\u221D" ~ B[0]^4),
       x=expression(B[0]),
       y=expression(M[min])) +
  theme_minimal()

############################################################
# PANEL D — SIZE BREADTH
############################################################
df_ratio <- df_clade %>%
  filter(!is.na(Mmin), !is.na(Mmax)) %>%
  mutate(size_ratio = Mmax / Mmin)

ratio_ref <- 10^(mean(log10(df_ratio$size_ratio)))

p4 <- ggplot(df_ratio, aes(B0, size_ratio)) +
  geom_point(size=2) +
  scale_x_log10() +
  scale_y_log10() +
  geom_hline(yintercept=ratio_ref, linetype="dashed", color="red") +
  geom_smooth(method="lm", se=FALSE) +
  annotate("text",
           x=min(df_ratio$B0),
           y=max(df_ratio$size_ratio),
           label=get_fit_label(fit_ratio),
           hjust=0, vjust=1) +
  labs(title=expression("D. Size breadth: " ~ M[max]/M[min] ~ "vs." ~ B[0]),
       x=expression(B[0]),
       y=expression(M[max]/M[min])) +
  theme_minimal()

############################################################
# PANEL E — B0 vs Mmax
############################################################
ref_E <- mean(log10(df_max$B0) - 0.25*log10(df_max$Mmax))

p5 <- ggplot(df_max, aes(Mmax, B0)) +
  geom_point(size=2) +
  scale_x_log10() +
  scale_y_log10() +
  geom_smooth(method="lm", se=FALSE) +
  geom_abline(slope=0.25, intercept=ref_E,
              linetype="dashed", color="red") +
  annotate("text",
           x=min(df_max$Mmax),
           y=max(df_max$B0),
           label=get_fit_label(fit_B0_Mmax),
           hjust=0, vjust=1) +
  labs(title=expression("E. Scaling: " ~ B[0] ~ "\u221D" ~ M[max]^{1/4}),
       x=expression(M[max]),
       y=expression(B[0])) +
  theme_minimal()

############################################################
# PANEL F — B0 vs Mmin
############################################################
ref_F <- mean(log10(df_min$B0) - 0.25*log10(df_min$Mmin))

p6 <- ggplot(df_min, aes(Mmin, B0)) +
  geom_point(size=2) +
  scale_x_log10() +
  scale_y_log10() +
  geom_smooth(method="lm", se=FALSE) +
  geom_abline(slope=0.25, intercept=ref_F,
              linetype="dashed", color="red") +
  annotate("text",
           x=min(df_min$Mmin),
           y=max(df_min$B0),
           label=get_fit_label(fit_B0_Mmin),
           hjust=0, vjust=1) +
  labs(title=expression("F. Scaling: " ~ B[0] ~ "\u221D" ~ M[min]^{1/4}),
       x=expression(M[min]),
       y=expression(B[0])) +
  theme_minimal()

############################################################
# COMBINE PANELS
############################################################
final_plot <- (p1 | p2) / (p3 | p4) / (p5 | p6)

print(final_plot)

############################################################
# SAVE FIGURE
############################################################
ggsave("bounded_scaling_6panel.png",
       final_plot,
       width=10,
       height=12,
       dpi=300)





########################################################
####
###
#
#



############################################################
# Load libraries
############################################################
library(dplyr)
library(readr)
library(ggplot2)
library(car)
library(patchwork)

############################################################
# Helper: slope + 95% CI
############################################################
get_fit_label <- function(fit) {
  slope <- coef(fit)[2]
  ci <- confint(fit)[2, ]
  sprintf("slope = %.2f (95%% CI: %.2f–%.2f)", slope, ci[1], ci[2])
}

############################################################
# 1. LOAD HOEHLER DATA
############################################################
file_path <- "/Users/brianjenquist/Desktop/Hoehler_etal_PNAS_MetabolicRateData_For_R.csv"

df_met <- read_csv(file_path)

df_met <- df_met %>%
  mutate(
    mass_g = Dry_Mass_g,
    metabolic_rate = Metabolic_Rate_W_at_25_C,
    mass_specific = metabolic_rate / mass_g,
    log_mass = log10(mass_g),
    log_ms = log10(mass_specific)
  ) %>%
  filter(is.finite(log_mass), is.finite(log_ms))

############################################################
# 2. ESTIMATE ENERGETIC BOUNDS
############################################################
df_bins <- df_met %>%
  mutate(size_bin = cut(log_mass, breaks = 25))

envelope <- df_bins %>%
  group_by(size_bin) %>%
  summarise(
    mass = 10^(mean(log_mass, na.rm=TRUE)),
    ms_max = max(mass_specific, na.rm=TRUE),
    ms_min = min(mass_specific, na.rm=TRUE),
    .groups="drop"
  )

BM_upper <- quantile(envelope$ms_max, 0.95, na.rm=TRUE)
BM_lower <- quantile(envelope$ms_min, 0.05, na.rm=TRUE)

############################################################
# 3. CLADE DATA
############################################################
df_clade <- data.frame(
  rank = 1:19,
  taxa = c("Unicells","Protozoa","Porifera","Anthozoa","Scyphozoa",
           "Nematoda","Mollusca","Branchiopoda","Oligochaeta",
           "Gymnolaemata","Malacostraca","Copepoda","Arachnida",
           "Insecta","Osteichthyes","Amphibia","Squamata",
           "Mammalia","Aves"),
  
  B0 = c(0.0365,0.0088,0.0247,0.0738,0.0135,
         0.0236,0.159,0.0570,0.0908,
         0.3080,0.3080,0.2115,0.0859,
         0.3655,0.2870,0.2960,0.3800,
         3.5900,3.8000),
  
  Mmin = c(1e-16,1e-12,NA,8e-11,NA,
           7.06e-11,9.1e-9,NA,2e-8,
           1e-5,7.4e-7,1.1e-8,1e-5,
           7.4e-9,2e-5,5e-4,5e-4,
           0.002,0.002),
  
  Mmax = c(4.7e-10,8e-8,NA,1e-5,NA,
           1.45e-7,250,NA,1.26e-5,
           0.1,2.8e-4,9.9e-6,0.1,
           0.1,2000,25,135,
           181400,156)
)

############################################################
# 4. PREDICTIONS
############################################################
df_clade <- df_clade %>%
  mutate(
    Mmin_pred = (B0 / BM_upper)^4,
    Mmax_pred = (B0 / BM_lower)^4
  )

df_min <- df_clade %>% filter(!is.na(Mmin))
df_max <- df_clade %>% filter(!is.na(Mmax))

############################################################
# 5. FIT MODELS
############################################################
fit_min <- lm(log10(Mmin) ~ log10(Mmin_pred), data=df_min)
fit_max <- lm(log10(Mmax) ~ log10(Mmax_pred), data=df_max)

fit_scaling_min <- lm(log10(Mmin) ~ log10(B0), data=df_min)
fit_scaling_max <- lm(log10(Mmax) ~ log10(B0), data=df_max)

fit_ratio <- lm(log10(Mmax/Mmin) ~ log10(B0), data=df_clade)

fit_B0_Mmax <- lm(log10(B0) ~ log10(Mmax), data=df_max)
fit_B0_Mmin <- lm(log10(B0) ~ log10(Mmin), data=df_min)

############################################################
# PANEL A — MIN SIZE
############################################################
p1 <- ggplot(df_min, aes(Mmin_pred, Mmin)) +
  geom_abline(slope=1, intercept=0, linetype="dashed", color="red") +
  geom_point(size=2) +
  scale_x_log10() +
  scale_y_log10() +
  geom_smooth(method="lm", se=FALSE) +
  annotate("text",
           x=min(df_min$Mmin_pred),
           y=max(df_min$Mmin),
           label=get_fit_label(fit_min),
           hjust=0, vjust=1) +
  labs(title="A. Minimum size prediction",
       x="Predicted Mmin",
       y="Observed Mmin") +
  theme_minimal()

############################################################
# PANEL B — MAX SIZE
############################################################
p2 <- ggplot(df_max, aes(Mmax_pred, Mmax)) +
  geom_abline(slope=1, intercept=0, linetype="dashed", color="red") +
  geom_point(size=2) +
  scale_x_log10() +
  scale_y_log10() +
  geom_smooth(method="lm", se=FALSE) +
  annotate("text",
           x=min(df_max$Mmax_pred),
           y=max(df_max$Mmax),
           label=get_fit_label(fit_max),
           hjust=0, vjust=1) +
  labs(title="B. Maximum size prediction",
       x="Predicted Mmax",
       y="Observed Mmax") +
  theme_minimal()

############################################################
# PANEL C — Mmin ∝ B0^4
############################################################
p3 <- ggplot(df_min, aes(B0, Mmin)) +
  geom_point(size=2) +
  scale_x_log10() +
  scale_y_log10() +
  geom_smooth(method="lm", se=FALSE) +
  annotate("text",
           x=min(df_min$B0),
           y=max(df_min$Mmin),
           label=get_fit_label(fit_scaling_min),
           hjust=0, vjust=1) +
  labs(title=expression(paste("C. Scaling: ", M[min], " ∝ ", B[0]^4)),
       x=expression(B[0]),
       y=expression(M[min])) +
  theme_minimal()

############################################################
# PANEL D — SIZE BREADTH
############################################################
df_ratio <- df_clade %>%
  filter(!is.na(Mmin), !is.na(Mmax)) %>%
  mutate(size_ratio = Mmax / Mmin)

ratio_ref <- 10^(mean(log10(df_ratio$size_ratio)))

p4 <- ggplot(df_ratio, aes(B0, size_ratio)) +
  geom_point(size=2) +
  scale_x_log10() +
  scale_y_log10() +
  geom_hline(yintercept=ratio_ref, linetype="dashed", color="red") +
  geom_smooth(method="lm", se=FALSE) +
  annotate("text",
           x=min(df_ratio$B0),
           y=max(df_ratio$size_ratio),
           label=get_fit_label(fit_ratio),
           hjust=0, vjust=1) +
  labs(title=expression(paste("D. Size breadth: ", M[max]/M[min], " vs ", B[0])),
       x=expression(B[0]),
       y=expression(M[max]/M[min])) +
  theme_minimal()

############################################################
# PANEL E — B0 ∝ Mmax^(1/4)
############################################################
ref_E <- mean(log10(df_max$B0) - 0.25*log10(df_max$Mmax))

p5 <- ggplot(df_max, aes(Mmax, B0)) +
  geom_point(size=2) +
  scale_x_log10() +
  scale_y_log10() +
  geom_smooth(method="lm", se=FALSE) +
  geom_abline(slope=0.25, intercept=ref_E,
              linetype="dashed", color="red") +
  annotate("text",
           x=min(df_max$Mmax),
           y=max(df_max$B0),
           label=get_fit_label(fit_B0_Mmax),
           hjust=0, vjust=1) +
  labs(title=expression(paste("E. Scaling: ", B[0], " ∝ ", M[max]^{1/4})),
       x=expression(M[max]),
       y=expression(B[0])) +
  theme_minimal()

############################################################
# PANEL F — B0 ∝ Mmin^(1/4)
############################################################
ref_F <- mean(log10(df_min$B0) - 0.25*log10(df_min$Mmin))

p6 <- ggplot(df_min, aes(Mmin, B0)) +
  geom_point(size=2) +
  scale_x_log10() +
  scale_y_log10() +
  geom_smooth(method="lm", se=FALSE) +
  geom_abline(slope=0.25, intercept=ref_F,
              linetype="dashed", color="red") +
  annotate("text",
           x=min(df_min$Mmin),
           y=max(df_min$B0),
           label=get_fit_label(fit_B0_Mmin),
           hjust=0, vjust=1) +
  labs(title=expression(paste("F. Scaling: ", B[0], " ∝ ", M[min]^{1/4})),
       x=expression(M[min]),
       y=expression(B[0])) +
  theme_minimal()

############################################################
# PANEL G — Mmax ∝ B0^4  (NEW)
############################################################
p7 <- ggplot(df_max, aes(B0, Mmax)) +
  geom_point(size=2) +
  scale_x_log10() +
  scale_y_log10() +
  geom_smooth(method="lm", se=FALSE) +
  annotate("text",
           x=min(df_max$B0),
           y=max(df_max$Mmax),
           label=get_fit_label(fit_scaling_max),
           hjust=0, vjust=1) +
  labs(title=expression(paste("G. Scaling: ", M[max], " ∝ ", B[0]^4)),
       x=expression(B[0]),
       y=expression(M[max])) +
  theme_minimal()

############################################################
# COMBINE PANELS
############################################################
final_plot <- (p1 | p2) / (p3 | p7) / (p4 | p5) / p6

print(final_plot)

############################################################
# SAVE
############################################################
ggsave("bounded_scaling_full.png",
       final_plot,
       width=10,
       height=14,
       dpi=300)









######################
######################
#####
###
##
#


############################################################
# Combine min and max into one dataset
############################################################
df_combined <- bind_rows(
  df_min %>% mutate(
    type = "Min",
    M_obs = Mmin,
    M_pred = Mmin_pred
  ),
  df_max %>% mutate(
    type = "Max",
    M_obs = Mmax,
    M_pred = Mmax_pred
  )
) %>%
  mutate(
    log_residual = log10(M_obs / M_pred),
    log_B0 = log10(B0)
  )

############################################################
# Fit model (test of bias)
############################################################
fit_resid <- lm(log_residual ~ log_B0, data=df_combined)

############################################################
# Plot
############################################################
p_single <- ggplot(df_combined, aes(B0, log_residual, shape=type)) +
  
  geom_point(size=3) +
  
  scale_x_log10() +
  
  # theoretical expectation: zero deviation
  geom_hline(yintercept=0,
             linetype="dashed",
             color="red",
             linewidth=0.8) +
  
  # fitted trend
  geom_smooth(method="lm", se=FALSE, color="blue") +
  
  annotate("text",
           x=min(df_combined$B0),
           y=max(df_combined$log_residual),
           label=get_fit_label(fit_resid),
           hjust=0, vjust=1) +
  
  labs(
    title="Macroevolutionary scaling test: predicted vs observed size",
    x=expression(B[0]),
    y=expression(log[10](M[obs] / M[pred]))
  ) +
  
  theme_classic() +
  theme(legend.title=element_blank())
aes(color=rank)
print(p_single)

############################################################
# Save
############################################################
ggsave("single_panel_test.png",
       p_single,
       width=6,
       height=5,
       dpi=300)




#########
########
#####
##
#



############################################################
# LOAD LIBRARIES
############################################################
library(dplyr)
library(readr)
library(ggplot2)
library(patchwork)

############################################################
# HELPER: slope + 95% CI
############################################################
get_fit_label <- function(fit) {
  slope <- coef(fit)[2]
  ci <- confint(fit)[2, ]
  sprintf("slope = %.2f (95%% CI: %.2f–%.2f)",
          slope, ci[1], ci[2])
}

############################################################
# 1. LOAD METABOLIC DATA
############################################################
file_path <- "/Users/brianjenquist/Desktop/Hoehler_etal_PNAS_MetabolicRateData_For_R.csv"

df_met <- read_csv(file_path)

df_met <- df_met %>%
  mutate(
    mass_g = Dry_Mass_g,
    metabolic_rate = Metabolic_Rate_W_at_25_C,
    mass_specific = metabolic_rate / mass_g,
    log_mass = log10(mass_g),
    log_ms = log10(mass_specific)
  ) %>%
  filter(is.finite(log_mass), is.finite(log_ms))

############################################################
# 2. ESTIMATE BOUNDS (MEAN ± 2 SD, LOG SCALE)
############################################################
log_ms_mean <- mean(df_met$log_ms, na.rm=TRUE)
log_ms_sd   <- sd(df_met$log_ms, na.rm=TRUE)

BM_upper <- 10^(log_ms_mean + 2*log_ms_sd)
BM_lower <- 10^(log_ms_mean - 2*log_ms_sd)

############################################################
# 3. CLADE DATA
############################################################
df_clade <- data.frame(
  rank = 1:19,
  taxa = c("Unicells","Protozoa","Porifera","Anthozoa","Scyphozoa",
           "Nematoda","Mollusca","Branchiopoda","Oligochaeta",
           "Gymnolaemata","Malacostraca","Copepoda","Arachnida",
           "Insecta","Osteichthyes","Amphibia","Squamata",
           "Mammalia","Aves"),
  
  B0 = c(0.0365,0.0088,0.0247,0.0738,0.0135,
         0.0236,0.159,0.0570,0.0908,
         0.3080,0.3080,0.2115,0.0859,
         0.3655,0.2870,0.2960,0.3800,
         3.5900,3.8000),
  
  Mmin = c(1e-16,1e-12,NA,8e-11,NA,
           7.06e-11,9.1e-9,NA,2e-8,
           1e-5,7.4e-7,1.1e-8,1e-5,
           7.4e-9,2e-5,5e-4,5e-4,
           0.002,0.002),
  
  Mmax = c(4.7e-10,8e-8,NA,1e-5,NA,
           1.45e-7,250,NA,1.26e-5,
           0.1,2.8e-4,9.9e-6,0.1,
           0.1,2000,25,135,
           181400,156)
)

############################################################
# 4. PREDICTIONS
############################################################
df_clade <- df_clade %>%
  mutate(
    Mmin_pred = (B0 / BM_upper)^4,
    Mmax_pred = (B0 / BM_lower)^4
  )

df_min <- df_clade %>% filter(!is.na(Mmin))
df_max <- df_clade %>% filter(!is.na(Mmax))

############################################################
# 5. FIT MODELS
############################################################
fit_min <- lm(log10(Mmin) ~ log10(Mmin_pred), data=df_min)
fit_max <- lm(log10(Mmax) ~ log10(Mmax_pred), data=df_max)

fit_scaling_min <- lm(log10(Mmin) ~ log10(B0), data=df_min)
fit_scaling_max <- lm(log10(Mmax) ~ log10(B0), data=df_max)

fit_ratio <- lm(log10(Mmax/Mmin) ~ log10(B0), data=df_clade)

fit_B0_Mmax <- lm(log10(B0) ~ log10(Mmax), data=df_max)
fit_B0_Mmin <- lm(log10(B0) ~ log10(Mmin), data=df_min)

############################################################
# THEORY INTERCEPTS
############################################################
int_min <- mean(log10(df_min$Mmin) - 4*log10(df_min$B0))
int_max <- mean(log10(df_max$Mmax) - 4*log10(df_max$B0))

int_E <- mean(log10(df_max$B0) - 0.25*log10(df_max$Mmax))
int_F <- mean(log10(df_min$B0) - 0.25*log10(df_min$Mmin))

############################################################
# PANEL A — MIN SIZE (BALANCED AXES)
############################################################

# X range (tight)
xlims_A <- range(log10(df_min$Mmin_pred), na.rm=TRUE)

# Add small padding to x
pad <- 0.2
xlims_A <- xlims_A + c(-pad, pad)

# Y range must include BOTH data and 1:1 line
ylims_A <- range(
  c(log10(df_min$Mmin), xlims_A),
  na.rm=TRUE
)

p1 <- ggplot(df_min, aes(x = log10(Mmin_pred),
                         y = log10(Mmin))) +
  
  geom_point(aes(color="Data"), size=2) +
  
  geom_abline(aes(linetype="Theory: 1:1"),
              slope=1, intercept=0,
              color="red", linewidth=1.2) +
  
  geom_smooth(aes(color="Fit"),
              method="lm", se=FALSE, linewidth=1.2) +
  
  coord_cartesian(xlim = xlims_A, ylim = ylims_A) +
  
  scale_color_manual(values=c("Data"="black","Fit"="blue")) +
  scale_linetype_manual(values=c("Theory: 1:1"="dashed")) +
  
  annotate("text",
           x=xlims_A[1],
           y=ylims_A[2],
           label=get_fit_label(fit_min),
           hjust=0, vjust=1) +
  
  labs(title="A. Minimum size prediction",
       x="log10(Predicted Mmin)",
       y="log10(Observed Mmin)",
       color="", linetype="") +
  
  theme_minimal()
############################################################
# PANEL B — MAX SIZE (BALANCED AXES)
############################################################

# X range (tight)
xlims_B <- range(log10(df_max$Mmax_pred), na.rm=TRUE)

# Small padding
pad <- 0.2
xlims_B <- xlims_B + c(-pad, pad)

# Y range includes data + 1:1 line
ylims_B <- range(
  c(log10(df_max$Mmax), xlims_B),
  na.rm=TRUE
)

p2 <- ggplot(df_max, aes(x = log10(Mmax_pred),
                         y = log10(Mmax))) +
  
  geom_point(aes(color="Data"), size=2) +
  
  geom_abline(aes(linetype="Theory: 1:1"),
              slope=1, intercept=0,
              color="red", linewidth=1.2) +
  
  geom_smooth(aes(color="Fit"),
              method="lm", se=FALSE, linewidth=1.2) +
  
  coord_cartesian(xlim = xlims_B, ylim = ylims_B) +
  
  scale_color_manual(values=c("Data"="black","Fit"="blue")) +
  scale_linetype_manual(values=c("Theory: 1:1"="dashed")) +
  
  annotate("text",
           x=xlims_B[1],
           y=ylims_B[2],
           label=get_fit_label(fit_max),
           hjust=0, vjust=1) +
  
  labs(title="B. Maximum size prediction",
       x="log10(Predicted Mmax)",
       y="log10(Observed Mmax)",
       color="", linetype="") +
  
  theme_minimal()
############################################################
# PANEL C
############################################################
p3 <- ggplot(df_min, aes(B0, Mmin)) +
  geom_point(size=2) +
  scale_x_log10() + scale_y_log10() +
  geom_smooth(method="lm", se=FALSE) +
  geom_abline(slope=4, intercept=int_min,
              linetype="dashed", color="red") +
  annotate("text", x=min(df_min$B0), y=max(df_min$Mmin),
           label=get_fit_label(fit_scaling_min), hjust=0, vjust=1) +
  labs(title=expression("C. " ~ M[min] %prop% B[0]^4),
       x=expression(B[0]), y=expression(M[min])) +
  theme_minimal()

############################################################
# PANEL D
############################################################
df_ratio <- df_clade %>%
  filter(!is.na(Mmin), !is.na(Mmax)) %>%
  mutate(size_ratio = Mmax/Mmin)

ratio_ref <- 10^(mean(log10(df_ratio$size_ratio)))

p4 <- ggplot(df_ratio, aes(B0, size_ratio)) +
  geom_point(size=2) +
  scale_x_log10() + scale_y_log10() +
  geom_hline(yintercept=ratio_ref, linetype="dashed", color="red") +
  geom_smooth(method="lm", se=FALSE) +
  annotate("text", x=min(df_ratio$B0), y=max(df_ratio$size_ratio),
           label=get_fit_label(fit_ratio), hjust=0, vjust=1) +
  labs(title=expression("D. " ~ M[max]/M[min]),
       x=expression(B[0]), y=expression(M[max]/M[min])) +
  theme_minimal()

############################################################
# PANEL E
############################################################
p5 <- ggplot(df_max, aes(Mmax, B0)) +
  geom_point(size=2) +
  scale_x_log10() + scale_y_log10() +
  geom_smooth(method="lm", se=FALSE) +
  geom_abline(slope=0.25, intercept=int_E,
              linetype="dashed", color="red") +
  annotate("text", x=min(df_max$Mmax), y=max(df_max$B0),
           label=get_fit_label(fit_B0_Mmax), hjust=0, vjust=1) +
  labs(title=expression("E. " ~ B[0] %prop% M[max]^{1/4}),
       x=expression(M[max]), y=expression(B[0])) +
  theme_minimal()

############################################################
# PANEL F
############################################################
p6 <- ggplot(df_min, aes(Mmin, B0)) +
  geom_point(size=2) +
  scale_x_log10() + scale_y_log10() +
  geom_smooth(method="lm", se=FALSE) +
  geom_abline(slope=0.25, intercept=int_F,
              linetype="dashed", color="red") +
  annotate("text", x=min(df_min$Mmin), y=max(df_min$B0),
           label=get_fit_label(fit_B0_Mmin), hjust=0, vjust=1) +
  labs(title=expression("F. " ~ B[0] %prop% M[min]^{1/4}),
       x=expression(M[min]), y=expression(B[0])) +
  theme_minimal()

############################################################
# PANEL G — DISTRIBUTION
############################################################
p7 <- ggplot(df_met, aes(x = log10(mass_specific))) +
  geom_histogram(bins=50, fill="grey70", color="black") +
  geom_vline(aes(xintercept=log10(BM_upper), color="+2 SD"),
             linetype="dashed") +
  geom_vline(aes(xintercept=log10(BM_lower), color="-2 SD"),
             linetype="dashed") +
  scale_color_manual(values=c("+2 SD"="red","-2 SD"="blue")) +
  labs(title="G. Distribution of log10(B/M)",
       x="log10(B/M)", y="Frequency",
       color="Statistical bounds") +
  theme_minimal()

############################################################
# PANEL H
############################################################
p8 <- ggplot(df_max, aes(B0, Mmax)) +
  geom_point(size=2) +
  scale_x_log10() + scale_y_log10() +
  geom_smooth(method="lm", se=FALSE) +
  geom_abline(slope=4, intercept=int_max,
              linetype="dashed", color="red") +
  annotate("text", x=min(df_max$B0), y=max(df_max$Mmax),
           label=get_fit_label(fit_scaling_max), hjust=0, vjust=1) +
  labs(title=expression("H. " ~ M[max] %prop% B[0]^4),
       x=expression(B[0]), y=expression(M[max])) +
  theme_minimal()

############################################################
# FINAL FIGURE
############################################################
final_plot <- (p1 | p2) /
  (p3 | p8) /
  (p4 | p7) /
  (p5 | p6)

print(final_plot)




#######################
##########
######
###

############################################################
# LOAD LIBRARIES
############################################################
library(dplyr)
library(readr)
library(ggplot2)
library(patchwork)

############################################################
# COLOR PALETTE (colorblind-safe)
############################################################
col_data <- "black"
col_fit  <- "#0072B2"   # blue
col_theory <- "#D55E00" # orange

############################################################
# HELPER: slope + 95% CI
############################################################
get_fit_label <- function(fit) {
  slope <- coef(fit)[2]
  ci <- confint(fit)[2, ]
  sprintf("slope = %.2f (95%% CI: %.2f–%.2f)",
          slope, ci[1], ci[2])
}

############################################################
# LOAD METABOLIC DATA
############################################################
file_path <- "/Users/brianjenquist/Desktop/Hoehler_etal_PNAS_MetabolicRateData_For_R.csv"

df_met <- read_csv(file_path)

df_met <- df_met %>%
  mutate(
    mass_g = Dry_Mass_g,
    metabolic_rate = Metabolic_Rate_W_at_25_C,
    mass_specific = metabolic_rate / mass_g,
    log_mass = log10(mass_g),
    log_ms = log10(mass_specific)
  ) %>%
  filter(is.finite(log_mass), is.finite(log_ms))

############################################################
# BOUNDS (±2 SD in log space)
############################################################
log_ms_mean <- mean(df_met$log_ms, na.rm=TRUE)
log_ms_sd   <- sd(df_met$log_ms, na.rm=TRUE)

BM_upper <- 10^(log_ms_mean + 2*log_ms_sd)
BM_lower <- 10^(log_ms_mean - 2*log_ms_sd)

############################################################
# CLADE DATA
############################################################
df_clade <- data.frame(
  rank = 1:19,
  B0 = c(0.0365,0.0088,0.0247,0.0738,0.0135,
         0.0236,0.159,0.0570,0.0908,
         0.3080,0.3080,0.2115,0.0859,
         0.3655,0.2870,0.2960,0.3800,
         3.5900,3.8000),
  Mmin = c(1e-16,1e-12,NA,8e-11,NA,
           7.06e-11,9.1e-9,NA,2e-8,
           1e-5,7.4e-7,1.1e-8,1e-5,
           7.4e-9,2e-5,5e-4,5e-4,
           0.002,0.002),
  Mmax = c(4.7e-10,8e-8,NA,1e-5,NA,
           1.45e-7,250,NA,1.26e-5,
           0.1,2.8e-4,9.9e-6,0.1,
           0.1,2000,25,135,
           181400,156)
)

############################################################
# PREDICTIONS
############################################################
df_clade <- df_clade %>%
  mutate(
    Mmin_pred = (B0 / BM_upper)^4,
    Mmax_pred = (B0 / BM_lower)^4
  )

df_min <- df_clade %>% filter(!is.na(Mmin))
df_max <- df_clade %>% filter(!is.na(Mmax))

############################################################
# MODELS
############################################################
fit_min <- lm(log10(Mmin) ~ log10(Mmin_pred), data=df_min)
fit_max <- lm(log10(Mmax) ~ log10(Mmax_pred), data=df_max)

fit_scaling_min <- lm(log10(Mmin) ~ log10(B0), data=df_min)
fit_scaling_max <- lm(log10(Mmax) ~ log10(B0), data=df_max)

df_ratio <- df_clade %>%
  filter(!is.na(Mmin), !is.na(Mmax)) %>%
  mutate(size_ratio = Mmax/Mmin)

fit_ratio <- lm(log10(size_ratio) ~ log10(B0), data=df_ratio)

fit_B0_Mmax <- lm(log10(B0) ~ log10(Mmax), data=df_max)
fit_B0_Mmin <- lm(log10(B0) ~ log10(Mmin), data=df_min)

############################################################
# INTERCEPTS
############################################################
int_min <- mean(log10(df_min$Mmin) - 4*log10(df_min$B0))
int_max <- mean(log10(df_max$Mmax) - 4*log10(df_max$B0))

int_E <- mean(log10(df_max$B0) - 0.25*log10(df_max$Mmax))
int_F <- mean(log10(df_min$B0) - 0.25*log10(df_min$Mmin))

############################################################
# PANEL A
############################################################
xlims_A <- range(log10(df_min$Mmin_pred))
pad <- 0.2
xlims_A <- xlims_A + c(-pad, pad)
ylims_A <- range(c(log10(df_min$Mmin), xlims_A))

p1 <- ggplot(df_min, aes(log10(Mmin_pred), log10(Mmin))) +
  geom_point(aes(color="Data"), size=2) +
  geom_abline(aes(linetype="1:1 line (Observed = Predicted)"),
              slope=1, intercept=0, color=col_theory, linewidth=1.3) +
  geom_smooth(aes(color="Fit"), method="lm", se=FALSE, linewidth=1) +
  coord_cartesian(xlim=xlims_A, ylim=ylims_A) +
  annotate("text", x=xlims_A[1], y=ylims_A[2],
           label=get_fit_label(fit_min),
           hjust=0, vjust=1, size=3.5) +
  scale_color_manual(values=c("Data"=col_data,"Fit"=col_fit)) +
  scale_linetype_manual(values=c("1:1 line (Observed = Predicted)"="dashed")) +
  labs(title="A. Minimum size prediction",
       x=expression(log[10](M[min]^pred)),
       y=expression(log[10](M[min]^obs)),
       color="", linetype="") +
  theme_minimal()

############################################################
# PANEL B
############################################################
xlims_B <- range(log10(df_max$Mmax_pred))
xlims_B <- xlims_B + c(-pad, pad)
ylims_B <- range(c(log10(df_max$Mmax), xlims_B))

p2 <- ggplot(df_max, aes(log10(Mmax_pred), log10(Mmax))) +
  geom_point(aes(color="Data"), size=2) +
  geom_abline(aes(linetype="1:1 line (Observed = Predicted)"),
              slope=1, intercept=0, color=col_theory, linewidth=1.3) +
  geom_smooth(aes(color="Fit"), method="lm", se=FALSE, linewidth=1) +
  coord_cartesian(xlim=xlims_B, ylim=ylims_B) +
  annotate("text", x=xlims_B[1], y=ylims_B[2],
           label=get_fit_label(fit_max),
           hjust=0, vjust=1, size=3.5) +
  scale_color_manual(values=c("Data"=col_data,"Fit"=col_fit)) +
  scale_linetype_manual(values=c("1:1 line (Observed = Predicted)"="dashed")) +
  labs(title="B. Maximum size prediction",
       x=expression(log[10](M[max]^pred)),
       y=expression(log[10](M[max]^obs)),
       color="", linetype="") +
  theme_minimal()

############################################################
# PANEL C
############################################################
p3 <- ggplot(df_min, aes(B0, Mmin)) +
  geom_point() +
  scale_x_log10() + scale_y_log10() +
  geom_abline(slope=4, intercept=int_min,
              linetype="dashed", color=col_theory) +
  geom_smooth(method="lm", se=FALSE, color=col_fit) +
  annotate("text", x=min(df_min$B0), y=max(df_min$Mmin),
           label=get_fit_label(fit_scaling_min),
           hjust=0, vjust=1, size=3.5) +
  labs(title=expression(italic(M[min]) %prop% italic(B[0])^4),
       x=expression(log[10](B[0])),
       y=expression(log[10](M[min]))) +
  theme_minimal()

############################################################
# PANEL D
############################################################
p4 <- ggplot(df_ratio, aes(B0, size_ratio)) +
  geom_point() +
  scale_x_log10() + scale_y_log10() +
  geom_smooth(method="lm", se=FALSE, color=col_fit) +
  annotate("text", x=min(df_ratio$B0), y=max(df_ratio$size_ratio),
           label=get_fit_label(fit_ratio),
           hjust=0, vjust=1, size=3.5) +
  labs(title=expression(italic(M[max])/italic(M[min]) ~ "vs" ~ italic(B[0])),
       x=expression(log[10](B[0])),
       y=expression(log[10](M[max]/M[min]))) +
  theme_minimal()

############################################################
# PANEL E
############################################################
p5 <- ggplot(df_max, aes(Mmax, B0)) +
  geom_point() +
  scale_x_log10() + scale_y_log10() +
  geom_abline(slope=0.25, intercept=int_E,
              linetype="dashed", color=col_theory) +
  geom_smooth(method="lm", se=FALSE, color=col_fit) +
  annotate("text", x=min(df_max$Mmax), y=max(df_max$B0),
           label=get_fit_label(fit_B0_Mmax),
           hjust=0, vjust=1, size=3.5) +
  labs(title=expression(italic(B[0]) %prop% italic(M[max])^{1/4}),
       x=expression(log[10](M[max])),
       y=expression(log[10](B[0]))) +
  theme_minimal()

############################################################
# PANEL F
############################################################
p6 <- ggplot(df_min, aes(Mmin, B0)) +
  geom_point() +
  scale_x_log10() + scale_y_log10() +
  geom_abline(slope=0.25, intercept=int_F,
              linetype="dashed", color=col_theory) +
  geom_smooth(method="lm", se=FALSE, color=col_fit) +
  annotate("text", x=min(df_min$Mmin), y=max(df_min$B0),
           label=get_fit_label(fit_B0_Mmin),
           hjust=0, vjust=1, size=3.5) +
  labs(title=expression(italic(B[0]) %prop% italic(M[min])^{1/4}),
       x=expression(log[10](M[min])),
       y=expression(log[10](B[0]))) +
  theme_minimal()

############################################################
# PANEL G
############################################################
p7 <- ggplot(df_met, aes(log10(mass_specific))) +
  geom_histogram(bins=50, fill="grey70", color="black") +
  geom_vline(aes(xintercept=log10(BM_upper), color="+2 SD"),
             linetype="dashed") +
  geom_vline(aes(xintercept=log10(BM_lower), color="-2 SD"),
             linetype="dashed") +
  scale_color_manual(values=c("+2 SD"=col_theory,"-2 SD"=col_fit)) +
  labs(title="G. Distribution of log10(B/M)",
       x=expression(log[10](B/M)),
       y="Frequency",
       color="Bounds") +
  theme_minimal()

############################################################
# PANEL H
############################################################
p8 <- ggplot(df_max, aes(B0, Mmax)) +
  geom_point() +
  scale_x_log10() + scale_y_log10() +
  geom_abline(slope=4, intercept=int_max,
              linetype="dashed", color=col_theory) +
  geom_smooth(method="lm", se=FALSE, color=col_fit) +
  annotate("text", x=min(df_max$B0), y=max(df_max$Mmax),
           label=get_fit_label(fit_scaling_max),
           hjust=0, vjust=1, size=3.5) +
  labs(title=expression(italic(M[max]) %prop% italic(B[0])^4),
       x=expression(log[10](B[0])),
       y=expression(log[10](M[max]))) +
  theme_minimal()

############################################################
# FINAL FIGURE
############################################################
final_plot <- (p1 | p2) /
  (p3 | p8) /
  (p4 | p7) /
  (p5 | p6)

print(final_plot)





##############
########################################################
############################
##############
########
############################################################
# LOAD LIBRARIES
############################################################
library(dplyr)
library(readr)
library(ggplot2)
library(patchwork)

############################################################
# COLORS (colorblind-safe)
############################################################
col_data   <- "black"
col_fit    <- "#0072B2"
col_theory <- "#D55E00"

############################################################
# HELPER: slope + 95% CI
############################################################
get_fit_label <- function(fit) {
  slope <- coef(fit)[2]
  ci <- confint(fit)[2, ]
  sprintf("slope = %.2f (95%% CI: %.2f–%.2f)",
          slope, ci[1], ci[2])
}

############################################################
# LOAD DATA
############################################################
file_path <- "/Users/brianjenquist/Desktop/Hoehler_etal_PNAS_MetabolicRateData_For_R.csv"

df_met <- read_csv(file_path) %>%
  mutate(
    mass_specific = Metabolic_Rate_W_at_25_C / Dry_Mass_g,
    log_ms = log10(mass_specific)
  ) %>%
  filter(is.finite(log_ms))

############################################################
# BOUNDS (±2 SD)
############################################################
mu  <- mean(df_met$log_ms, na.rm=TRUE)
sdv <- sd(df_met$log_ms, na.rm=TRUE)

BM_upper <- 10^(mu + 2*sdv)
BM_lower <- 10^(mu - 2*sdv)

############################################################
# CLADE DATA
############################################################
df_clade <- data.frame(
  B0 = c(0.0365,0.0088,0.0247,0.0738,0.0135,
         0.0236,0.159,0.0570,0.0908,
         0.3080,0.3080,0.2115,0.0859,
         0.3655,0.2870,0.2960,0.3800,
         3.5900,3.8000),
  Mmin = c(1e-16,1e-12,NA,8e-11,NA,
           7.06e-11,9.1e-9,NA,2e-8,
           1e-5,7.4e-7,1.1e-8,1e-5,
           7.4e-9,2e-5,5e-4,5e-4,
           0.002,0.002),
  Mmax = c(4.7e-10,8e-8,NA,1e-5,NA,
           1.45e-7,250,NA,1.26e-5,
           0.1,2.8e-4,9.9e-6,0.1,
           0.1,2000,25,135,
           181400,156)
)

############################################################
# PREDICTIONS
############################################################
df_clade <- df_clade %>%
  mutate(
    Mmin_pred = (B0 / BM_upper)^4,
    Mmax_pred = (B0 / BM_lower)^4
  )

df_min <- df_clade %>% filter(!is.na(Mmin))
df_max <- df_clade %>% filter(!is.na(Mmax))

############################################################
# MODELS
############################################################
fit_min <- lm(log10(Mmin) ~ log10(Mmin_pred), df_min)
fit_max <- lm(log10(Mmax) ~ log10(Mmax_pred), df_max)

fit_scaling_min <- lm(log10(Mmin) ~ log10(B0), df_min)
fit_scaling_max <- lm(log10(Mmax) ~ log10(B0), df_max)

df_ratio <- df_clade %>%
  filter(!is.na(Mmin), !is.na(Mmax)) %>%
  mutate(size_ratio = Mmax/Mmin)

fit_ratio <- lm(log10(size_ratio) ~ log10(B0), df_ratio)

############################################################
# PANEL A (FIXED LEGEND)
############################################################
lineA <- data.frame(
  x = seq(min(log10(df_min$Mmin_pred)), max(log10(df_min$Mmin_pred)), length.out=100)
)
lineA$y <- lineA$x

ylimA <- range(c(lineA$x, log10(df_min$Mmin))) + c(-0.3,0.3)

p1 <- ggplot(df_min, aes(log10(Mmin_pred), log10(Mmin))) +
  geom_point(aes(color="Data")) +
  geom_line(data=lineA,
            aes(x=x, y=y, color="1:1 line", linetype="1:1 line"),
            linewidth=1.2) +
  geom_smooth(aes(color="Fit"), method="lm", se=FALSE) +
  coord_cartesian(ylim=ylimA) +
  annotate("text",
           x=min(lineA$x),
           y=ylimA[2],
           label=get_fit_label(fit_min),
           hjust=0, vjust=1) +
  scale_color_manual(values=c("Data"=col_data,"Fit"=col_fit,"1:1 line"=col_theory)) +
  scale_linetype_manual(values=c("1:1 line"="dashed")) +
  labs(
    title=expression("Panel A: " ~ italic(M[min]^obs) ~ "vs" ~ italic(M[min]^pred)),
    x=expression(log[10](M[min]^pred)),
    y=expression(log[10](M[min]^obs)),
    color="", linetype=""
  ) +
  theme_minimal()

############################################################
# PANEL B (FIXED LEGEND)
############################################################
lineB <- data.frame(
  x = seq(min(log10(df_max$Mmax_pred)), max(log10(df_max$Mmax_pred)), length.out=100)
)
lineB$y <- lineB$x

ylimB <- range(c(lineB$x, log10(df_max$Mmax))) + c(-0.3,0.3)

p2 <- ggplot(df_max, aes(log10(Mmax_pred), log10(Mmax))) +
  geom_point(aes(color="Data")) +
  geom_line(data=lineB,
            aes(x=x, y=y, color="1:1 line", linetype="1:1 line"),
            linewidth=1.2) +
  geom_smooth(aes(color="Fit"), method="lm", se=FALSE) +
  coord_cartesian(ylim=ylimB) +
  annotate("text",
           x=min(lineB$x),
           y=ylimB[2],
           label=get_fit_label(fit_max),
           hjust=0, vjust=1) +
  scale_color_manual(values=c("Data"=col_data,"Fit"=col_fit,"1:1 line"=col_theory)) +
  scale_linetype_manual(values=c("1:1 line"="dashed")) +
  labs(
    title=expression("Panel B: " ~ italic(M[max]^obs) ~ "vs" ~ italic(M[max]^pred)),
    x=expression(log[10](M[max]^pred)),
    y=expression(log[10](M[max]^obs)),
    color="", linetype=""
  ) +
  theme_minimal()

############################################################
# PANEL G (FIXED LEGEND)
############################################################
p5 <- ggplot(df_met, aes(log_ms)) +
  geom_histogram(bins=50, fill="grey70", color="black") +
  geom_vline(aes(xintercept=log10(BM_upper),
                 color="+2 SD",
                 linetype="+2 SD"),
             linewidth=1.2) +
  geom_vline(aes(xintercept=log10(BM_lower),
                 color="−2 SD",
                 linetype="−2 SD"),
             linewidth=1.2) +
  scale_color_manual(values=c("+2 SD"=col_theory,"−2 SD"=col_fit)) +
  scale_linetype_manual(values=c("+2 SD"="dashed","−2 SD"="dashed")) +
  labs(
    title="Panel G: Distribution of log10(B/M)",
    x=expression(log[10](B/M)),
    y="Frequency",
    color="", linetype=""
  ) +
  theme_minimal()

############################################################
# REMAINING PANELS (unchanged)
############################################################
p3 <- ggplot(df_min, aes(B0, Mmin)) +
  geom_point() +
  scale_x_log10() + scale_y_log10() +
  geom_smooth(method="lm", se=FALSE, color=col_fit) +
  annotate("text",
           x=min(df_min$B0),
           y=max(df_min$Mmin),
           label=get_fit_label(fit_scaling_min),
           hjust=0, vjust=1) +
  labs(
    title=expression("Panel C: " ~ italic(M[min]) %prop% italic(B[0])^4),
    x=expression(log[10](B[0])),
    y=expression(log[10](M[min]))
  ) +
  theme_minimal()

p4 <- ggplot(df_ratio, aes(log10(B0), log10(size_ratio))) +
  geom_point() +
  geom_smooth(method="lm", se=FALSE, color=col_fit) +
  labs(
    title=expression("Panel D: " ~ log[10](M[max]/M[min]) ~ "vs" ~ log[10](B[0])),
    x=expression(log[10](B[0])),
    y=expression(log[10](M[max]/M[min]))
  ) +
  theme_minimal()

p6 <- ggplot(df_max, aes(B0, Mmax)) +
  geom_point() +
  scale_x_log10() + scale_y_log10() +
  geom_smooth(method="lm", se=FALSE, color=col_fit) +
  annotate("text",
           x=min(df_max$B0),
           y=max(df_max$Mmax),
           label=get_fit_label(fit_scaling_max),
           hjust=0, vjust=1) +
  labs(
    title=expression("Panel H: " ~ italic(M[max]) %prop% italic(B[0])^4),
    x=expression(log[10](B[0])),
    y=expression(log[10](M[max]))
  ) +
  theme_minimal()

############################################################
# FINAL FIGURE
############################################################
final_plot <- (p1 | p2) /
  (p3 | p6) /
  (p4 | p5)

print(final_plot)







###############  new plot using observed max and min B/M to calculate the predicted 1:1 lines in panel A and B

############################################################
# LOAD LIBRARIES
############################################################
library(dplyr)
library(readr)
library(ggplot2)
library(patchwork)

############################################################
# COLORS
############################################################
col_data   <- "black"
col_fit    <- "#0072B2"
col_theory <- "#D55E00"

############################################################
# HELPER: slope + 95% CI
############################################################
get_fit_label <- function(fit) {
  slope <- coef(fit)[2]
  ci <- confint(fit)[2, ]
  sprintf("slope = %.2f (95%% CI: %.2f–%.2f)",
          slope, ci[1], ci[2])
}

############################################################
# LOAD DATA
############################################################
file_path <- "/Users/brianjenquist/Desktop/Hoehler_etal_PNAS_MetabolicRateData_For_R.csv"

df_met <- read_csv(file_path) %>%
  mutate(
    mass_specific = Metabolic_Rate_W_at_25_C / Dry_Mass_g,
    log_ms = log10(mass_specific)
  ) %>%
  filter(is.finite(log_ms))

############################################################
# BOUNDS
############################################################
mu  <- mean(df_met$log_ms, na.rm=TRUE)
sdv <- sd(df_met$log_ms, na.rm=TRUE)

BM_upper <- 10^(mu + 2*sdv)
BM_lower <- 10^(mu - 2*sdv)

############################################################
# CLADE DATA
############################################################
df_clade <- data.frame(
  B0 = c(0.0365,0.0088,0.0247,0.0738,0.0135,
         0.0236,0.159,0.0570,0.0908,
         0.3080,0.3080,0.2115,0.0859,
         0.3655,0.2870,0.2960,0.3800,
         3.5900,3.8000),
  Mmin = c(1e-16,1e-12,NA,8e-11,NA,
           7.06e-11,9.1e-9,NA,2e-8,
           1e-5,7.4e-7,1.1e-8,1e-5,
           7.4e-9,2e-5,5e-4,5e-4,
           0.002,0.002),
  Mmax = c(4.7e-10,8e-8,NA,1e-5,NA,
           1.45e-7,250,NA,1.26e-5,
           0.1,2.8e-4,9.9e-6,0.1,
           0.1,2000,25,135,
           181400,156)
)

############################################################
# PREDICTIONS
############################################################
df_clade <- df_clade %>%
  mutate(
    Mmin_pred = (B0 / BM_upper)^4,
    Mmax_pred = (B0 / BM_lower)^4
  )

df_min <- df_clade %>% filter(!is.na(Mmin))
df_max <- df_clade %>% filter(!is.na(Mmax))

############################################################
# MODELS
############################################################
fit_min <- lm(log10(Mmin) ~ log10(Mmin_pred), df_min)
fit_max <- lm(log10(Mmax) ~ log10(Mmax_pred), df_max)

fit_scaling_min <- lm(log10(Mmin) ~ log10(B0), df_min)
fit_scaling_max <- lm(log10(Mmax) ~ log10(B0), df_max)

df_ratio <- df_clade %>%
  filter(!is.na(Mmin), !is.na(Mmax)) %>%
  mutate(size_ratio = Mmax/Mmin)

fit_ratio <- lm(log10(size_ratio) ~ log10(B0), df_ratio)

############################################################
# PANEL D (FINAL FIXED VERSION)
############################################################
yD <- range(log10(df_ratio$size_ratio), na.rm=TRUE)
expand_factor <- 0.6
y_span <- diff(yD)

ylimD <- c(
  yD[1] - expand_factor * y_span,
  yD[2] + expand_factor * y_span
)

p4 <- ggplot(df_ratio, aes(log10(B0), log10(size_ratio))) +
  geom_point(color=col_data) +
  geom_smooth(method="lm", se=FALSE, color=col_fit) +
  
  coord_cartesian(ylim=ylimD) +
  
  annotate("text",
           x=min(log10(df_ratio$B0)),
           y=ylimD[2],
           label=get_fit_label(fit_ratio),
           hjust=0, vjust=1) +
  
  labs(
    title=expression("Panel D: " ~ log[10](M[max]/M[min]) ~ "vs" ~ log[10](B[0])),
    x=expression(log[10](B[0])),
    y=expression(log[10](M[max]/M[min]))
  ) +
  
  theme_minimal()



#### Panels A–B test theoretical predictions for minimum and maximum body size derived from bounds on mass-specific metabolic rate (B/M). Predicted limits follow M_min∝(B_0/(B/M)_max ┤ )^4,M_max∝(B_0/(B/M)_min ┤ )^4, where B_0is the normalization constant of the metabolic scaling relationship. Panel A shows observed versus predicted minimum body mass (M_min ). The dashed line denotes the 1:1 expectation (Observed = Predicted). The fitted regression closely follows the 1:1 line, indicating that minimum body size lies near the theoretical upper bound on mass-specific metabolic rate. Panel B shows observed versus predicted maximum body mass (M_max ). The dashed line denotes the 1:1 expectation. Observed values systematically fall below this line, indicating that maximum body size does not saturate the theoretical lower bound on mass-specific metabolic rate. Panels C and H show scaling relationships between body size limits and metabolic normalization, with M_min∝B_0^4and M_max∝B_0^4. Fitted slopes and 95% confidence intervals are shown. These relationships are consistent with theoretical expectations derived from metabolic scaling. Panel D shows the logarithmic size range 〖log⁡〗_10 (M_max/M_min)as a function of 〖log⁡〗_10 (B_0). The weak slope and wide confidence interval indicate that variation in B_0explains limited variation in size range across clades. Panel G shows the distribution of mass-specific metabolic rate 〖log⁡〗_10 (B/M)across taxa. Vertical dashed lines denote empirical bounds defined as ±2 standard deviations from the mean, which are used to derive theoretical limits on body size. Points represent clade-level data. Solid lines indicate fitted regressions. Dashed lines indicate theoretical expectations or constraint boundaries.



### now lets generate predicted Mmax and Mmin based on empircal data 


############################################################
# LOAD LIBRARIES
############################################################
library(dplyr)
library(readr)
library(ggplot2)
library(patchwork)

############################################################
# COLORS (colorblind-safe)
############################################################
col_data   <- "black"
col_fit    <- "#0072B2"
col_theory <- "#D55E00"

############################################################
# HELPER: slope + 95% CI
############################################################
get_fit_label <- function(fit) {
  slope <- coef(fit)[2]
  ci <- confint(fit)[2, ]
  sprintf("slope = %.2f (95%% CI: %.2f–%.2f)",
          slope, ci[1], ci[2])
}

############################################################
# LOAD DATA
############################################################
file_path <- "/Users/brianjenquist/Desktop/Hoehler_etal_PNAS_MetabolicRateData_For_R.csv"

df_met <- read_csv(file_path) %>%
  mutate(
    mass_specific = Metabolic_Rate_W_at_25_C / Dry_Mass_g,
    log_ms = log10(mass_specific)
  ) %>%
  filter(is.finite(log_ms))

############################################################
# EMPIRICAL BOUNDS (ROBUST: 1–99% QUANTILES)
############################################################
BM_upper <- quantile(df_met$mass_specific, 0.99, na.rm=TRUE)
BM_lower <- quantile(df_met$mass_specific, 0.01, na.rm=TRUE)

############################################################
# CLADE DATA
############################################################
df_clade <- data.frame(
  B0 = c(0.0365,0.0088,0.0247,0.0738,0.0135,
         0.0236,0.159,0.0570,0.0908,
         0.3080,0.3080,0.2115,0.0859,
         0.3655,0.2870,0.2960,0.3800,
         3.5900,3.8000),
  Mmin = c(1e-16,1e-12,NA,8e-11,NA,
           7.06e-11,9.1e-9,NA,2e-8,
           1e-5,7.4e-7,1.1e-8,1e-5,
           7.4e-9,2e-5,5e-4,5e-4,
           0.002,0.002),
  Mmax = c(4.7e-10,8e-8,NA,1e-5,NA,
           1.45e-7,250,NA,1.26e-5,
           0.1,2.8e-4,9.9e-6,0.1,
           0.1,2000,25,135,
           181400,156)
)

############################################################
# PREDICTED LIMITS
############################################################
df_clade <- df_clade %>%
  mutate(
    Mmin_pred = (B0 / BM_upper)^4,
    Mmax_pred = (B0 / BM_lower)^4
  )

df_min <- df_clade %>% filter(!is.na(Mmin))
df_max <- df_clade %>% filter(!is.na(Mmax))

############################################################
# MODELS
############################################################
fit_min <- lm(log10(Mmin) ~ log10(Mmin_pred), df_min)
fit_max <- lm(log10(Mmax) ~ log10(Mmax_pred), df_max)

fit_scaling_min <- lm(log10(Mmin) ~ log10(B0), df_min)
fit_scaling_max <- lm(log10(Mmax) ~ log10(B0), df_max)

df_ratio <- df_clade %>%
  filter(!is.na(Mmin), !is.na(Mmax)) %>%
  mutate(size_ratio = Mmax/Mmin)

fit_ratio <- lm(log10(size_ratio) ~ log10(B0), df_ratio)

############################################################
# PANEL A (Mmin)
############################################################
lineA <- data.frame(
  x = seq(min(log10(df_min$Mmin_pred)),
          max(log10(df_min$Mmin_pred)), length.out=100)
)
lineA$y <- lineA$x

ylimA <- range(c(lineA$x, log10(df_min$Mmin))) + c(-0.4,0.4)

p1 <- ggplot(df_min, aes(log10(Mmin_pred), log10(Mmin))) +
  geom_point(aes(color="Data")) +
  geom_line(data=lineA,
            aes(x=x, y=y, color="1:1 line", linetype="1:1 line"),
            linewidth=1.2) +
  geom_smooth(aes(color="Fit"), method="lm", se=FALSE) +
  coord_cartesian(ylim=ylimA) +
  annotate("text",
           x=min(lineA$x),
           y=ylimA[2],
           label=get_fit_label(fit_min),
           hjust=0, vjust=1) +
  scale_color_manual(values=c("Data"=col_data,
                              "Fit"=col_fit,
                              "1:1 line"=col_theory)) +
  scale_linetype_manual(values=c("1:1 line"="dashed")) +
  labs(
    title=expression("Panel A: " ~ italic(M[min]^obs) ~ "vs" ~ italic(M[min]^pred)),
    x=expression(log[10](M[min]^pred)),
    y=expression(log[10](M[min]^obs)),
    color="", linetype=""
  ) +
  theme_minimal()

############################################################
# PANEL B (Mmax)
############################################################
lineB <- data.frame(
  x = seq(min(log10(df_max$Mmax_pred)),
          max(log10(df_max$Mmax_pred)), length.out=100)
)
lineB$y <- lineB$x

ylimB <- range(c(lineB$x, log10(df_max$Mmax))) + c(-0.4,0.4)

p2 <- ggplot(df_max, aes(log10(Mmax_pred), log10(Mmax))) +
  geom_point(aes(color="Data")) +
  geom_line(data=lineB,
            aes(x=x, y=y, color="1:1 line", linetype="1:1 line"),
            linewidth=1.2) +
  geom_smooth(aes(color="Fit"), method="lm", se=FALSE) +
  coord_cartesian(ylim=ylimB) +
  annotate("text",
           x=min(lineB$x),
           y=ylimB[2],
           label=get_fit_label(fit_max),
           hjust=0, vjust=1) +
  scale_color_manual(values=c("Data"=col_data,
                              "Fit"=col_fit,
                              "1:1 line"=col_theory)) +
  scale_linetype_manual(values=c("1:1 line"="dashed")) +
  labs(
    title=expression("Panel B: " ~ italic(M[max]^obs) ~ "vs" ~ italic(M[max]^pred)),
    x=expression(log[10](M[max]^pred)),
    y=expression(log[10](M[max]^obs)),
    color="", linetype=""
  ) +
  theme_minimal()

############################################################
# PANEL C
############################################################
p3 <- ggplot(df_min, aes(B0, Mmin)) +
  geom_point() +
  scale_x_log10() + scale_y_log10() +
  geom_smooth(method="lm", se=FALSE, color=col_fit) +
  annotate("text",
           x=min(df_min$B0),
           y=max(df_min$Mmin),
           label=get_fit_label(fit_scaling_min),
           hjust=0, vjust=1) +
  labs(
    title=expression("Panel C: " ~ italic(M[min]) %prop% italic(B[0])^4),
    x=expression(log[10](B[0])),
    y=expression(log[10](M[min]))
  ) +
  theme_minimal()

############################################################
# PANEL D (expanded + CI)
############################################################
yD <- range(log10(df_ratio$size_ratio))
span <- diff(yD)
ylimD <- c(yD[1] - 0.6*span, yD[2] + 0.6*span)

p4 <- ggplot(df_ratio, aes(log10(B0), log10(size_ratio))) +
  geom_point() +
  geom_smooth(method="lm", se=FALSE, color=col_fit) +
  coord_cartesian(ylim=ylimD) +
  annotate("text",
           x=min(log10(df_ratio$B0)),
           y=ylimD[2],
           label=get_fit_label(fit_ratio),
           hjust=0, vjust=1) +
  labs(
    title=expression("Panel D: " ~ log[10](M[max]/M[min]) ~ "vs" ~ log[10](B[0])),
    x=expression(log[10](B[0])),
    y=expression(log[10](M[max]/M[min]))
  ) +
  theme_minimal()

############################################################
# PANEL G (distribution)
############################################################
p5 <- ggplot(df_met, aes(log_ms)) +
  geom_histogram(bins=50, fill="grey70", color="black") +
  geom_vline(xintercept=log10(BM_upper),
             color=col_theory, linetype="dashed") +
  geom_vline(xintercept=log10(BM_lower),
             color=col_fit, linetype="dashed") +
  labs(
    title="Panel G: Distribution of log10(B/M)",
    x=expression(log[10](B/M)),
    y="Frequency"
  ) +
  theme_minimal()

############################################################
# PANEL H
############################################################
p6 <- ggplot(df_max, aes(B0, Mmax)) +
  geom_point() +
  scale_x_log10() + scale_y_log10() +
  geom_smooth(method="lm", se=FALSE, color=col_fit) +
  annotate("text",
           x=min(df_max$B0),
           y=max(df_max$Mmax),
           label=get_fit_label(fit_scaling_max),
           hjust=0, vjust=1) +
  labs(
    title=expression("Panel H: " ~ italic(M[max]) %prop% italic(B[0])^4),
    x=expression(log[10](B[0])),
    y=expression(log[10](M[max]))
  ) +
  theme_minimal()

############################################################
# FINAL FIGURE
############################################################
final_plot <- (p1 | p2) /
  (p3 | p6) /
  (p4 | p5)

print(final_plot)




################

############################################################
# LOAD LIBRARIES
############################################################
library(dplyr)
library(readr)
library(ggplot2)
library(patchwork)

############################################################
# COLORS (colorblind-safe)
############################################################
col_data   <- "black"
col_fit    <- "#0072B2"
col_theory <- "#D55E00"

############################################################
# HELPER FUNCTION: slope + 95% CI
############################################################
get_fit_label <- function(fit) {
  slope <- coef(fit)[2]
  ci <- confint(fit)[2, ]
  sprintf("slope = %.2f (95%% CI: %.2f–%.2f)",
          slope, ci[1], ci[2])
}

############################################################
# LOAD GLOBAL METABOLIC DATA (Panel G)
############################################################
file_path <- "/Users/brianjenquist/Desktop/Hoehler_etal_PNAS_MetabolicRateData_For_R.csv"

df_met <- read_csv(file_path) %>%
  mutate(
    mass_specific = Metabolic_Rate_W_at_25_C / Dry_Mass_g,
    log_ms = log10(mass_specific)
  ) %>%
  filter(is.finite(log_ms))

############################################################
# EMPIRICAL BOUNDS (ROBUST QUANTILES)
############################################################
BM_upper <- quantile(df_met$mass_specific, 0.99, na.rm=TRUE)
BM_lower <- quantile(df_met$mass_specific, 0.01, na.rm=TRUE)

############################################################
# CLADE DATA
############################################################
df_clade <- data.frame(
  Group = c(
    "Prokaryotes","Protists","Algae","Fungi","Diatoms",
    "Zooplankton","Insects","Arachnids","Crustaceans",
    "Fish","Amphibians","Reptiles","Birds",
    "Mammals","Angiosperms","Gymnosperms","Ferns",
    "Trees","Large Trees"
  ),
  B0 = c(0.0365,0.0088,0.0247,0.0738,0.0135,
         0.0236,0.159,0.0570,0.0908,
         0.3080,0.3080,0.2115,0.0859,
         0.3655,0.2870,0.2960,0.3800,
         3.5900,3.8000),
  Mmin = c(1e-16,1e-12,NA,8e-11,NA,
           7.06e-11,9.1e-9,NA,2e-8,
           1e-5,7.4e-7,1.1e-8,1e-5,
           7.4e-9,2e-5,5e-4,5e-4,
           0.002,0.002),
  Mmax = c(4.7e-10,8e-8,NA,1e-5,NA,
           1.45e-7,250,NA,1.26e-5,
           0.1,2.8e-4,9.9e-6,0.1,
           0.1,2000,25,135,
           181400,156)
)

############################################################
# PREDICTED SIZE LIMITS
############################################################
df_clade <- df_clade %>%
  mutate(
    Mmin_pred = (B0 / BM_upper)^4,
    Mmax_pred = (B0 / BM_lower)^4
  )

df_min <- df_clade %>% filter(!is.na(Mmin))
df_max <- df_clade %>% filter(!is.na(Mmax))

############################################################
# MODELS
############################################################
fit_min <- lm(log10(Mmin) ~ log10(Mmin_pred), df_min)
fit_max <- lm(log10(Mmax) ~ log10(Mmax_pred), df_max)

fit_scaling_min <- lm(log10(Mmin) ~ log10(B0), df_min)
fit_scaling_max <- lm(log10(Mmax) ~ log10(B0), df_max)

df_ratio <- df_clade %>%
  filter(!is.na(Mmin), !is.na(Mmax)) %>%
  mutate(size_ratio = Mmax / Mmin)

fit_ratio <- lm(log10(size_ratio) ~ log10(B0), df_ratio)

############################################################
# PANEL A (Mmin)
############################################################
lineA <- data.frame(
  x = seq(min(log10(df_min$Mmin_pred)),
          max(log10(df_min$Mmin_pred)), length.out=100)
)
lineA$y <- lineA$x

ylimA <- range(c(lineA$x, log10(df_min$Mmin))) + c(-0.4, 0.4)

p1 <- ggplot(df_min, aes(log10(Mmin_pred), log10(Mmin))) +
  geom_point(aes(color="Data")) +
  geom_line(data=lineA,
            aes(x=x, y=y, color="1:1 line", linetype="1:1 line"),
            linewidth=1.2) +
  geom_smooth(aes(color="Fit"), method="lm", se=FALSE) +
  coord_cartesian(ylim=ylimA) +
  annotate("text",
           x=min(lineA$x),
           y=ylimA[2],
           label=get_fit_label(fit_min),
           hjust=0, vjust=1) +
  scale_color_manual(values=c(
    "Data"=col_data,
    "Fit"=col_fit,
    "1:1 line"=col_theory
  )) +
  scale_linetype_manual(values=c("1:1 line"="dashed")) +
  labs(
    title=expression("Panel A: " ~ italic(M[min]^obs) ~ "vs" ~ italic(M[min]^pred)),
    x=expression(log[10](M[min]^pred)),
    y=expression(log[10](M[min]^obs)),
    color="", linetype=""
  ) +
  theme_minimal()

############################################################
# PANEL B (Mmax)
############################################################
lineB <- data.frame(
  x = seq(min(log10(df_max$Mmax_pred)),
          max(log10(df_max$Mmax_pred)), length.out=100)
)
lineB$y <- lineB$x

ylimB <- range(c(lineB$x, log10(df_max$Mmax))) + c(-0.4, 0.4)

p2 <- ggplot(df_max, aes(log10(Mmax_pred), log10(Mmax))) +
  geom_point(aes(color="Data")) +
  geom_line(data=lineB,
            aes(x=x, y=y, color="1:1 line", linetype="1:1 line"),
            linewidth=1.2) +
  geom_smooth(aes(color="Fit"), method="lm", se=FALSE) +
  coord_cartesian(ylim=ylimB) +
  annotate("text",
           x=min(lineB$x),
           y=ylimB[2],
           label=get_fit_label(fit_max),
           hjust=0, vjust=1) +
  scale_color_manual(values=c(
    "Data"=col_data,
    "Fit"=col_fit,
    "1:1 line"=col_theory
  )) +
  scale_linetype_manual(values=c("1:1 line"="dashed")) +
  labs(
    title=expression("Panel B: " ~ italic(M[max]^obs) ~ "vs" ~ italic(M[max]^pred)),
    x=expression(log[10](M[max]^pred)),
    y=expression(log[10](M[max]^obs)),
    color="", linetype=""
  ) +
  theme_minimal()

############################################################
# PANEL C
############################################################
p3 <- ggplot(df_min, aes(B0, Mmin)) +
  geom_point() +
  scale_x_log10() + scale_y_log10() +
  geom_smooth(method="lm", se=FALSE, color=col_fit) +
  annotate("text",
           x=min(df_min$B0),
           y=max(df_min$Mmin),
           label=get_fit_label(fit_scaling_min),
           hjust=0, vjust=1) +
  labs(
    title=expression("Panel C: " ~ italic(M[min]) %prop% italic(B[0])^4),
    x=expression(log[10](B[0])),
    y=expression(log[10](M[min]))
  ) +
  theme_minimal()

############################################################
# PANEL D
############################################################
yD <- range(log10(df_ratio$size_ratio))
span <- diff(yD)
ylimD <- c(yD[1] - 0.6*span, yD[2] + 0.6*span)

p4 <- ggplot(df_ratio, aes(log10(B0), log10(size_ratio))) +
  geom_point() +
  geom_smooth(method="lm", se=FALSE, color=col_fit) +
  coord_cartesian(ylim=ylimD) +
  annotate("text",
           x=min(log10(df_ratio$B0)),
           y=ylimD[2],
           label=get_fit_label(fit_ratio),
           hjust=0, vjust=1) +
  labs(
    title=expression("Panel D: " ~ log[10](M[max]/M[min]) ~ "vs" ~ log[10](B[0])),
    x=expression(log[10](B[0])),
    y=expression(log[10](M[max]/M[min]))
  ) +
  theme_minimal()

############################################################
# PANEL G
############################################################
p5 <- ggplot(df_met, aes(log_ms)) +
  geom_histogram(bins=50, fill="grey70", color="black") +
  geom_vline(xintercept=log10(BM_upper),
             color=col_theory, linetype="dashed") +
  geom_vline(xintercept=log10(BM_lower),
             color=col_fit, linetype="dashed") +
  labs(
    title="Panel G: Distribution of log10(B/M)",
    x=expression(log[10](B/M)),
    y="Frequency"
  ) +
  theme_minimal()

############################################################
# PANEL H
############################################################
p6 <- ggplot(df_max, aes(B0, Mmax)) +
  geom_point() +
  scale_x_log10() + scale_y_log10() +
  geom_smooth(method="lm", se=FALSE, color=col_fit) +
  annotate("text",
           x=min(df_max$B0),
           y=max(df_max$Mmax),
           label=get_fit_label(fit_scaling_max),
           hjust=0, vjust=1) +
  labs(
    title=expression("Panel H: " ~ italic(M[max]) %prop% italic(B[0])^4),
    x=expression(log[10](B[0])),
    y=expression(log[10](M[max]))
  ) +
  theme_minimal()

############################################################
# FINAL MULTI-PANEL FIGURE
############################################################
final_plot <- (p1 | p2) /
  (p3 | p6) /
  (p4 | p5)

print(final_plot)




####

############################################################
# PANEL I: Residual comparison (Mmin vs Mmax)
############################################################

# Compute residuals
df_resid <- df_clade %>%
  mutate(
    resid_min = log10(Mmin) - log10(Mmin_pred),
    resid_max = log10(Mmax) - log10(Mmax_pred)
  ) %>%
  select(Group, resid_min, resid_max) %>%
  tidyr::pivot_longer(
    cols = c(resid_min, resid_max),
    names_to = "Type",
    values_to = "Residual"
  ) %>%
  mutate(
    Type = recode(Type,
                  resid_min = "Mmin",
                  resid_max = "Mmax")
  ) %>%
  filter(is.finite(Residual))

# Plot
p_resid <- ggplot(df_resid, aes(Type, Residual, fill=Type)) +
  
  geom_boxplot(width=0.5, alpha=0.6, outlier.shape=NA) +
  
  geom_jitter(width=0.1, size=2, alpha=0.8) +
  
  geom_hline(yintercept=0,
             linetype="dashed",
             color="black") +
  
  scale_fill_manual(values=c(
    "Mmin" = col_fit,
    "Mmax" = col_theory
  )) +
  
  labs(
    title="Panel I: Deviation from 1:1 prediction",
    x="",
    y=expression(log[10](Observed) - log[10](Predicted))
  ) +
  
  theme_minimal() +
  theme(legend.position="none")

print(p_resid)





###################################
############################################################
# LOAD LIBRARIES
############################################################
library(dplyr)
library(tidyr)
library(readr)
library(ggplot2)
library(patchwork)

############################################################
# COLORS
############################################################
col_data   <- "black"
col_fit    <- "#0072B2"
col_theory <- "#D55E00"

############################################################
# HELPER FUNCTION
############################################################
get_fit_label <- function(fit) {
  slope <- coef(fit)[2]
  ci <- confint(fit)[2, ]
  sprintf("slope = %.2f (95%% CI: %.2f–%.2f)",
          slope, ci[1], ci[2])
}

############################################################
# LOAD METABOLIC DATA
############################################################
file_path <- "/Users/brianjenquist/Desktop/Hoehler_etal_PNAS_MetabolicRateData_For_R.csv"

df_met <- read_csv(file_path) %>%
  mutate(
    mass_specific = Metabolic_Rate_W_at_25_C / Dry_Mass_g,
    log_ms = log10(mass_specific)
  ) %>%
  filter(is.finite(log_ms))

############################################################
# EMPIRICAL BOUNDS (1–99% QUANTILES)
############################################################
BM_upper <- quantile(df_met$mass_specific, 0.99, na.rm=TRUE)
BM_lower <- quantile(df_met$mass_specific, 0.01, na.rm=TRUE)

############################################################
# CLADE DATA
############################################################
df_clade <- data.frame(
  Group = c(
    "Prokaryotes","Protists","Algae","Fungi","Diatoms",
    "Zooplankton","Insects","Arachnids","Crustaceans",
    "Fish","Amphibians","Reptiles","Birds",
    "Mammals","Angiosperms","Gymnosperms","Ferns",
    "Trees","Large Trees"
  ),
  B0 = c(0.0365,0.0088,0.0247,0.0738,0.0135,
         0.0236,0.159,0.0570,0.0908,
         0.3080,0.3080,0.2115,0.0859,
         0.3655,0.2870,0.2960,0.3800,
         3.5900,3.8000),
  Mmin = c(1e-16,1e-12,NA,8e-11,NA,
           7.06e-11,9.1e-9,NA,2e-8,
           1e-5,7.4e-7,1.1e-8,1e-5,
           7.4e-9,2e-5,5e-4,5e-4,
           0.002,0.002),
  Mmax = c(4.7e-10,8e-8,NA,1e-5,NA,
           1.45e-7,250,NA,1.26e-5,
           0.1,2.8e-4,9.9e-6,0.1,
           0.1,2000,25,135,
           181400,156)
)

############################################################
# PREDICTIONS
############################################################
df_clade <- df_clade %>%
  mutate(
    Mmin_pred = (B0 / BM_upper)^4,
    Mmax_pred = (B0 / BM_lower)^4
  )

df_min <- df_clade %>% filter(!is.na(Mmin))
df_max <- df_clade %>% filter(!is.na(Mmax))

############################################################
# MODELS
############################################################
fit_min <- lm(log10(Mmin) ~ log10(Mmin_pred), df_min)
fit_max <- lm(log10(Mmax) ~ log10(Mmax_pred), df_max)

fit_scaling_min <- lm(log10(Mmin) ~ log10(B0), df_min)
fit_scaling_max <- lm(log10(Mmax) ~ log10(B0), df_max)

df_ratio <- df_clade %>%
  filter(!is.na(Mmin), !is.na(Mmax)) %>%
  mutate(size_ratio = Mmax/Mmin)

fit_ratio <- lm(log10(size_ratio) ~ log10(B0), df_ratio)

############################################################
# PANEL A
############################################################
lineA <- data.frame(
  x = seq(min(log10(df_min$Mmin_pred)),
          max(log10(df_min$Mmin_pred)), length.out=100)
)
lineA$y <- lineA$x

ylimA <- range(c(lineA$x, log10(df_min$Mmin))) + c(-0.4, 0.4)

p1 <- ggplot(df_min, aes(log10(Mmin_pred), log10(Mmin))) +
  geom_point(aes(color="Data")) +
  geom_line(data=lineA,
            aes(x=x, y=y, color="1:1 line", linetype="1:1 line"),
            linewidth=1.2) +
  geom_smooth(aes(color="Fit"), method="lm", se=FALSE) +
  coord_cartesian(ylim=ylimA) +
  annotate("text",
           x=min(lineA$x),
           y=ylimA[2],
           label=get_fit_label(fit_min),
           hjust=0, vjust=1) +
  scale_color_manual(values=c("Data"=col_data,
                              "Fit"=col_fit,
                              "1:1 line"=col_theory)) +
  scale_linetype_manual(values=c("1:1 line"="dashed")) +
  labs(title="Panel A") +
  theme_minimal()

############################################################
# PANEL B
############################################################
lineB <- data.frame(
  x = seq(min(log10(df_max$Mmax_pred)),
          max(log10(df_max$Mmax_pred)), length.out=100)
)
lineB$y <- lineB$x

ylimB <- range(c(lineB$x, log10(df_max$Mmax))) + c(-0.4, 0.4)

p2 <- ggplot(df_max, aes(log10(Mmax_pred), log10(Mmax))) +
  geom_point(aes(color="Data")) +
  geom_line(data=lineB,
            aes(x=x, y=y, color="1:1 line", linetype="1:1 line"),
            linewidth=1.2) +
  geom_smooth(aes(color="Fit"), method="lm", se=FALSE) +
  coord_cartesian(ylim=ylimB) +
  annotate("text",
           x=min(lineB$x),
           y=ylimB[2],
           label=get_fit_label(fit_max),
           hjust=0, vjust=1) +
  scale_color_manual(values=c("Data"=col_data,
                              "Fit"=col_fit,
                              "1:1 line"=col_theory)) +
  scale_linetype_manual(values=c("1:1 line"="dashed")) +
  labs(title="Panel B") +
  theme_minimal()

############################################################
# PANEL D (ratio)
############################################################
yD <- range(log10(df_ratio$size_ratio))
span <- diff(yD)
ylimD <- c(yD[1] - 0.6*span, yD[2] + 0.6*span)

p4 <- ggplot(df_ratio, aes(log10(B0), log10(size_ratio))) +
  geom_point() +
  geom_smooth(method="lm", se=FALSE, color=col_fit) +
  coord_cartesian(ylim=ylimD) +
  annotate("text",
           x=min(log10(df_ratio$B0)),
           y=ylimD[2],
           label=get_fit_label(fit_ratio),
           hjust=0, vjust=1) +
  labs(title="Panel D") +
  theme_minimal()

############################################################
# PANEL G
############################################################
p5 <- ggplot(df_met, aes(log_ms)) +
  geom_histogram(bins=50, fill="grey70", color="black") +
  geom_vline(xintercept=log10(BM_upper),
             color=col_theory, linetype="dashed") +
  geom_vline(xintercept=log10(BM_lower),
             color=col_fit, linetype="dashed") +
  labs(title="Panel G") +
  theme_minimal()

############################################################
# PANEL I (RESIDUALS)
############################################################
df_resid <- df_clade %>%
  mutate(
    resid_min = log10(Mmin) - log10(Mmin_pred),
    resid_max = log10(Mmax) - log10(Mmax_pred)
  ) %>%
  dplyr::select(Group, resid_min, resid_max) %>%
  tidyr::pivot_longer(
    cols = c(resid_min, resid_max),
    names_to = "Type",
    values_to = "Residual"
  ) %>%
  mutate(
    Type = recode(Type,
                  resid_min = "Mmin",
                  resid_max = "Mmax")
  ) %>%
  filter(is.finite(Residual))

p_resid <- ggplot(df_resid, aes(Type, Residual, fill=Type)) +
  geom_boxplot(width=0.5, alpha=0.6, outlier.shape=NA) +
  geom_jitter(width=0.1, size=2) +
  geom_hline(yintercept=0, linetype="dashed") +
  scale_fill_manual(values=c("Mmin"=col_fit,
                             "Mmax"=col_theory)) +
  labs(title="Panel I: Residuals") +
  theme_minimal()

############################################################
# FINAL FIGURE
############################################################
final_plot <- (p1 | p2) /
  (p4 | p5) /
  p_resid

print(final_plot)


###############







############################################################
# Load libraries
############################################################
library(dplyr)
library(readr)
library(ggplot2)
library(patchwork)

############################################################
# Helper: slope + 95% CI
############################################################
get_fit_label <- function(fit) {
  slope <- coef(fit)[2]
  ci <- confint(fit)[2, ]
  sprintf("slope = %.2f (95%% CI: %.2f–%.2f)", slope, ci[1], ci[2])
}

############################################################
# 1. LOAD HOEHLER DATA
############################################################
file_path <- "/Users/brianjenquist/Desktop/Hoehler_etal_PNAS_MetabolicRateData_For_R.csv"

df_met <- read_csv(file_path) %>%
  mutate(
    mass = Dry_Mass_g,
    metabolic_rate = Metabolic_Rate_W_at_25_C,
    mass_specific = metabolic_rate / mass,
    log_mass = log10(mass)
  ) %>%
  filter(is.finite(log_mass), is.finite(mass_specific))

############################################################
# 2. ESTIMATE ENERGETIC BOUNDS
############################################################
df_bins <- df_met %>%
  mutate(size_bin = cut(log_mass, breaks = 25))

envelope <- df_bins %>%
  group_by(size_bin) %>%
  summarise(
    ms_max = max(mass_specific, na.rm=TRUE),
    ms_min = min(mass_specific, na.rm=TRUE),
    .groups="drop"
  )

BM_upper <- quantile(envelope$ms_max, 0.95, na.rm=TRUE)
BM_lower <- quantile(envelope$ms_min, 0.05, na.rm=TRUE)

############################################################
# 3. CLADE DATA
############################################################
df_clade <- data.frame(
  rank = 1:19,
  taxa = c("Unicells","Protozoa","Porifera","Anthozoa","Scyphozoa",
           "Nematoda","Mollusca","Branchiopoda","Oligochaeta",
           "Gymnolaemata","Malacostraca","Copepoda","Arachnida",
           "Insecta","Osteichthyes","Amphibia","Squamata",
           "Mammalia","Aves"),
  
  B0 = c(0.0365,0.0088,0.0247,0.0738,0.0135,
         0.0236,0.159,0.0570,0.0908,
         0.3080,0.3080,0.2115,0.0859,
         0.3655,0.2870,0.2960,0.3800,
         3.5900,3.8000),
  
  Mmin = c(1e-16,1e-12,NA,8e-11,NA,
           7.06e-11,9.1e-9,NA,2e-8,
           1e-5,7.4e-7,1.1e-8,1e-5,
           7.4e-9,2e-5,5e-4,5e-4,
           0.002,0.002),
  
  Mmax = c(4.7e-10,8e-8,NA,1e-5,NA,
           1.45e-7,250,NA,1.26e-5,
           0.1,2.8e-4,9.9e-6,0.1,
           0.1,2000,25,135,
           181400,156)
)

############################################################
# 4. PREDICTIONS
############################################################
df_clade <- df_clade %>%
  mutate(
    Mmin_pred = (B0 / BM_upper)^4,
    Mmax_pred = (B0 / BM_lower)^4
  )

df_min <- df_clade %>% filter(!is.na(Mmin))
df_max <- df_clade %>% filter(!is.na(Mmax))

############################################################
# 5. SHARED AXIS LIMITS (CRITICAL FIX)
############################################################
axis_vals <- c(df_min$Mmin, df_min$Mmin_pred,
               df_max$Mmax, df_max$Mmax_pred)

axis_limits <- range(axis_vals, na.rm=TRUE)

############################################################
# 6. FITS
############################################################
fit_min <- lm(log10(Mmin) ~ log10(Mmin_pred), data=df_min)
fit_max <- lm(log10(Mmax) ~ log10(Mmax_pred), data=df_max)

fit_scaling <- lm(log10(Mmin) ~ log10(B0), data=df_min)

df_ratio <- df_clade %>%
  filter(!is.na(Mmin), !is.na(Mmax)) %>%
  mutate(size_ratio = Mmax / Mmin)

fit_ratio <- lm(log10(size_ratio) ~ log10(B0), data=df_ratio)

############################################################
# PANEL A — MIN SIZE
############################################################
p1 <- ggplot(df_min, aes(Mmin_pred, Mmin)) +
  geom_abline(slope=1, intercept=0,
              linetype="dashed", color="red") +
  geom_point(size=2) +
  geom_smooth(method="lm", se=FALSE) +
  scale_x_log10(limits = axis_limits) +
  scale_y_log10(limits = axis_limits) +
  annotate("text",
           x=min(df_min$Mmin_pred),
           y=max(df_min$Mmin),
           label=get_fit_label(fit_min),
           hjust=0, vjust=1) +
  labs(title="A. Minimum size prediction",
       x="Predicted",
       y="Observed") +
  theme_classic()

############################################################
# PANEL B — MAX SIZE (FIXED)
############################################################
p2 <- ggplot(df_max, aes(Mmax_pred, Mmax)) +
  geom_abline(slope=1, intercept=0,
              linetype="dashed", color="red") +
  geom_point(size=2) +
  geom_smooth(method="lm", se=FALSE) +
  scale_x_log10(limits = axis_limits) +
  scale_y_log10(limits = axis_limits) +
  annotate("text",
           x=min(df_max$Mmax_pred),
           y=max(df_max$Mmax),
           label=get_fit_label(fit_max),
           hjust=0, vjust=1) +
  labs(title="B. Maximum size prediction",
       x="Predicted",
       y="Observed") +
  theme_classic()

############################################################
# PANEL C — SCALING
############################################################
ref_C <- mean(log10(df_min$Mmin) - 4 * log10(df_min$B0), na.rm=TRUE)

p3 <- ggplot(df_min, aes(B0, Mmin)) +
  geom_point(size=2) +
  geom_smooth(method="lm", se=FALSE) +
  geom_abline(slope=4, intercept=ref_C,
              linetype="dashed", color="red") +
  scale_x_log10() +
  scale_y_log10() +
  annotate("text",
           x=min(df_min$B0),
           y=max(df_min$Mmin),
           label=get_fit_label(fit_scaling),
           hjust=0, vjust=1) +
  labs(title=expression("C. Scaling: " ~ M[min] ~ propto ~ B[0]^4),
       x=expression(B[0]),
       y=expression(M[min])) +
  theme_classic()

############################################################
# PANEL D — CONSTRAINT
############################################################
ratio_ref <- 10^(mean(log10(df_ratio$size_ratio)))

p4 <- ggplot(df_ratio, aes(B0, size_ratio)) +
  geom_point(size=2) +
  geom_hline(yintercept=ratio_ref,
             linetype="dashed", color="red") +
  geom_smooth(method="lm", se=FALSE) +
  scale_x_log10() +
  scale_y_log10() +
  annotate("text",
           x=min(df_ratio$B0),
           y=max(df_ratio$size_ratio),
           label=get_fit_label(fit_ratio),
           hjust=0, vjust=1) +
  labs(title=expression("D. Constraint: " ~ M[max]/M[min] ~ " vs " ~ B[0]),
       x=expression(B[0]),
       y=expression(M[max]/M[min])) +
  theme_classic()

############################################################
# COMBINE PANELS
############################################################
final_plot <- (p1 | p2) / (p3 | p4)

print(final_plot)

############################################################
# SAVE
############################################################
ggsave("final_matched_axes_figure.png",
       final_plot,
       width=8,
       height=8,
       dpi=300)





#########
######################

############################################################
# Load libraries
############################################################
library(dplyr)
library(readr)
library(ggplot2)
library(patchwork)

############################################################
# Helper
############################################################
get_fit_label <- function(fit) {
  slope <- coef(fit)[2]
  ci <- confint(fit)[2, ]
  sprintf("slope = %.2f (95%% CI: %.2f–%.2f)", slope, ci[1], ci[2])
}

############################################################
# LOAD HOEHLER DATA
############################################################
file_path <- "/Users/brianjenquist/Desktop/Hoehler_etal_PNAS_MetabolicRateData_For_R.csv"

df_met <- read_csv(file_path) %>%
  mutate(
    mass = Dry_Mass_g,
    metabolic_rate = Metabolic_Rate_W_at_25_C,
    mass_specific = metabolic_rate / mass,
    log_mass = log10(mass)
  ) %>%
  filter(is.finite(log_mass), is.finite(mass_specific))

############################################################
# ESTIMATE ENERGETIC BOUNDS
############################################################
df_bins <- df_met %>%
  mutate(size_bin = cut(log_mass, breaks = 25))

envelope <- df_bins %>%
  group_by(size_bin) %>%
  summarise(
    ms_max = max(mass_specific, na.rm=TRUE),
    ms_min = min(mass_specific, na.rm=TRUE),
    .groups="drop"
  )

BM_upper <- quantile(envelope$ms_max, 0.95, na.rm=TRUE)
BM_lower <- quantile(envelope$ms_min, 0.05, na.rm=TRUE)

############################################################
# CLADE DATA
############################################################
df_clade <- data.frame(
  rank = 1:19,
  taxa = c("Unicells","Protozoa","Porifera","Anthozoa","Scyphozoa",
           "Nematoda","Mollusca","Branchiopoda","Oligochaeta",
           "Gymnolaemata","Malacostraca","Copepoda","Arachnida",
           "Insecta","Osteichthyes","Amphibia","Squamata",
           "Mammalia","Aves"),
  
  B0 = c(0.0365,0.0088,0.0247,0.0738,0.0135,
         0.0236,0.159,0.0570,0.0908,
         0.3080,0.3080,0.2115,0.0859,
         0.3655,0.2870,0.2960,0.3800,
         3.5900,3.8000),
  
  Mmin = c(1e-16,1e-12,NA,8e-11,NA,
           7.06e-11,9.1e-9,NA,2e-8,
           1e-5,7.4e-7,1.1e-8,1e-5,
           7.4e-9,2e-5,5e-4,5e-4,
           0.002,0.002),
  
  Mmax = c(4.7e-10,8e-8,NA,1e-5,NA,
           1.45e-7,250,NA,1.26e-5,
           0.1,2.8e-4,9.9e-6,0.1,
           0.1,2000,25,135,
           181400,156)
)

############################################################
# PREDICTIONS
############################################################
df_clade <- df_clade %>%
  mutate(
    Mmin_pred = (B0 / BM_upper)^4,
    Mmax_pred = (B0 / BM_lower)^4
  )

df_min <- df_clade %>% filter(!is.na(Mmin))
df_max <- df_clade %>% filter(!is.na(Mmax))

############################################################
# SHARED AXIS LIMITS
############################################################
axis_vals <- c(df_min$Mmin, df_min$Mmin_pred,
               df_max$Mmax, df_max$Mmax_pred)

axis_limits <- range(axis_vals, na.rm=TRUE)

############################################################
# FITS
############################################################
fit_min <- lm(log10(Mmin) ~ log10(Mmin_pred), data=df_min)
fit_max <- lm(log10(Mmax) ~ log10(Mmax_pred), data=df_max)

fit_scaling_min <- lm(log10(Mmin) ~ log10(B0), data=df_min)
fit_scaling_max <- lm(log10(Mmax) ~ log10(B0), data=df_max)

fit_B0_Mmin <- lm(log10(B0) ~ log10(Mmin), data=df_min)
fit_B0_Mmax <- lm(log10(B0) ~ log10(Mmax), data=df_max)

############################################################
# PANEL A — MIN
############################################################
p1 <- ggplot(df_min, aes(Mmin_pred, Mmin)) +
  geom_abline(slope=1, intercept=0, linetype="dashed", color="red") +
  geom_point(size=2) +
  geom_smooth(method="lm", se=FALSE) +
  scale_x_log10(limits=axis_limits) +
  scale_y_log10(limits=axis_limits) +
  labs(title="A. Minimum size",
       x="Predicted minimum body mass",
       y="Observed minimum body mass") +
  theme_classic()

############################################################
# PANEL B — MAX
############################################################
p2 <- ggplot(df_max, aes(Mmax_pred, Mmax)) +
  geom_abline(slope=1, intercept=0, linetype="dashed", color="red") +
  geom_point(size=2) +
  geom_smooth(method="lm", se=FALSE) +
  scale_x_log10(limits=axis_limits) +
  scale_y_log10(limits=axis_limits) +
  labs(title="B. Maximum size",
       x="Predicted maximum body mass",
       y="Observed maximum body mass") +
  theme_classic()

############################################################
# PANEL C — Mmin ∝ B0^4
############################################################
p3 <- ggplot(df_min, aes(B0, Mmin)) +
  geom_point(size=2) +
  geom_smooth(method="lm", se=FALSE) +
  scale_x_log10() +
  scale_y_log10() +
  labs(title=expression("C. Scaling: " ~ M[min] ~ propto ~ B[0]^4),
       x=expression(B[0]),
       y=expression(M[min])) +
  theme_classic()

############################################################
# PANEL D — Mmax ∝ B0^4
############################################################
p4 <- ggplot(df_max, aes(B0, Mmax)) +
  geom_point(size=2) +
  geom_smooth(method="lm", se=FALSE) +
  scale_x_log10() +
  scale_y_log10() +
  labs(title=expression("D. Scaling: " ~ M[max] ~ propto ~ B[0]^4),
       x=expression(B[0]),
       y=expression(M[max])) +
  theme_classic()

############################################################
# PANEL E — B0 ∝ Mmin^(1/4)
############################################################
p5 <- ggplot(df_min, aes(Mmin, B0)) +
  geom_point(size=2) +
  geom_smooth(method="lm", se=FALSE) +
  scale_x_log10() +
  scale_y_log10() +
  labs(title=expression("E. Scaling: " ~ B[0] ~ propto ~ M[min]^{1/4}),
       x=expression(M[min]),
       y=expression(B[0])) +
  theme_classic()

############################################################
# PANEL F — B0 ∝ Mmax^(1/4)
############################################################
p6 <- ggplot(df_max, aes(Mmax, B0)) +
  geom_point(size=2) +
  geom_smooth(method="lm", se=FALSE) +
  scale_x_log10() +
  scale_y_log10() +
  labs(title=expression("F. Scaling: " ~ B[0] ~ propto ~ M[max]^{1/4}),
       x=expression(M[max]),
       y=expression(B[0])) +
  theme_classic()

############################################################
# COMBINE
############################################################
final_plot <- (p1 | p2) / (p3 | p4) / (p5 | p6)

print(final_plot)

ggsave("final_full_multiplot.png",
       final_plot,
       width=10,
       height=12,
       dpi=300)




#############





