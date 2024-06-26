#' Variance Covariance Computation for GLMM
#'
#' Computes robust variance-covariance matrix for generalized linear mixed models
#' fitted with `glmer` from the `lme4` package. It allows specification of
#' clustering and supports different types of variance estimations.
#'
#' @name vcovCR.glmerModZY
#' @param obj A `glmerMod` object representing the fitted model.
#' @param cluster Optional; a vector indicating the cluster structure within the data.
#'                If NULL, attempts to retrieve cluster information from attributes of the model object.
#' @param type Character string specifying the type of variance-covariance matrix to compute.
#'             Supported types include "classic", with potential for further types depending on method implementation.
#'
#' @return Returns a diagonal matrix with the computed variances for each fixed effect in the model.
#'
#' @export
#' @importFrom lme4 glmer
#' @importFrom matrixStats rowSums
#' @importFrom stats setNames
#'

library("WoodburyMatrix")
library("sandwich")
library("clubSandwich")
library("lme4")
vcovCR.glmerModZY <- function(obj, cluster = NULL, type = "classic") {
  # put some check here to ensure the input is correct
  # If cluster not specified, will be set to attr(obj,"cluster")
  if (is.null(cluster)) {
    cluster <- attr(obj, "cluster")
  }

  link <- family(obj)$link

  beta <- matrix(fixef(obj), ncol = 1)

  np <- length(beta)

  gamma <- matrix(unlist(ranef(obj)), ncol = 1)

  nq <- length(gamma)

  X <- model.matrix(obj,type = "fixed")
  Z <- model.matrix(obj, type = "random")  # Z matrix for random effects
  Y <- obj@resp$y

  eta <- predict(obj, type = "link")
  ginv_eta <- predict(obj, type = "response")

  if (link == "identity"){
    delta = diag(nobs(obj)) # diag matrix
    deltainv = diag(1/diag(delta))# a more efficient way to get solve(delta)
  }

  else if (link == "logit"){
    delta <- diag(exp(eta)/(1+exp(eta))^2)
    deltainv <- diag(1/diag(delta))
  }

  else if (link == "log") {
    delta <- diag(exp(eta))
    deltainv <- diag(1/diag(delta))
  }

  P <- deltainv %*% (Y - ginv_eta) + eta
  e <- matrix(P - X %*% beta, ncol = 1)
  XtVX <- vcov(obj)  # model based variance
  #theta <- as.data.frame(VarCorr(obj)) # This is where the problem is, when you fit different models, this is different

  sigma2 <- sigma(obj)^2
  lambda <- getME(obj,"Lambda")
  R <- lambda %*% t(lambda) * sigma2

  G <- ngrps(obj)["fcluster"]
  sum <- matrix(0, np, np)

  for (g in 1:G){
    grp = ctdata$fcluster == g
    ng = sum(grp)

    # V = Z[grp,]%*%R%*%t(Z[grp,]) + deltainv[grp,grp]%*%Sigma%*%deltainv[grp,grp]
    # Vinv = solve(V)
    Sigma <- sigma2 * diag(ng)
    WB_A <- diag(1/diag(deltainv[grp,grp]%*%Sigma%*%deltainv[grp,grp]))

    WB_U <- Z[grp,]
    WB_C <- solve(R)
    WB_V <- t(Z[grp,])

    W <- WoodburyMatrix(A = WB_A, U = WB_U, B = WB_C, V = WB_V)
    Vinv <- solve(W)

    H = X[grp, ] %*% XtVX %*% t(X[grp, ]) %*% Vinv
    Q = t(X[grp, ]) %*% Vinv %*% X[grp, ] %*% XtVX

    # if loop, choose A, F and c based on robust variance form specified by the input 'type'
    F = diag(ng)
    A = diag(np)

    sum = sum + A %*% t(X[grp, ]) %*% Vinv %*% t(F) %*% e[grp, ] %*% t(e[grp, ]) %*% F %*% Vinv %*% X[grp, ] %*% A
  }

  c = 1
  robustVar <- c * XtVX %*% sum %*% XtVX
  diag(robustVar)  # Return diagonal elements representing the variances
}
