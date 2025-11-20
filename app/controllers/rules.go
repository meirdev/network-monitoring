package controllers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/meirdev/network-monitoring/api/common"
	"github.com/meirdev/network-monitoring/api/services"
)

type RuleController struct {
	RuleService *services.RuleService
}

func NewRuleController(ruleService *services.RuleService) *RuleController {
	return &RuleController{
		RuleService: ruleService,
	}
}

func (c *RuleController) GetRules(ctx *gin.Context) {
	rules, err := c.RuleService.GetRules(ctx.Request.Context())
	if err != nil {
		ctx.JSON(http.StatusInternalServerError, common.NewResponseWithError(err))
		return
	}

	ctx.JSON(http.StatusOK, common.NewResponseSuccess(rules))
}

func (c *RuleController) GetRule(ctx *gin.Context) {
	ruleId := ctx.Param("rule_id")

	rule, err := c.RuleService.GetRule(ctx.Request.Context(), ruleId)
	if err != nil {
		ctx.JSON(http.StatusInternalServerError, common.NewResponseWithError(err))
		return
	}

	ctx.JSON(http.StatusOK, common.NewResponseSuccess(rule))
}

func (c *RuleController) AddRule(ctx *gin.Context) {
	var rule services.Rule
	if err := ctx.ShouldBindJSON(&rule); err != nil {
		ctx.JSON(http.StatusBadRequest, common.NewResponseWithError(err))
		return
	}

	id, err := c.RuleService.AddRule(ctx.Request.Context(), rule)
	if err != nil {
		ctx.JSON(http.StatusInternalServerError, common.NewResponseWithError(err))
		return
	}

	rule.Id = *id

	ctx.JSON(http.StatusCreated, common.NewResponseSuccess(rule))
}

func (c *RuleController) UpdateRule(ctx *gin.Context) {
	var rule services.Rule
	if err := ctx.ShouldBindJSON(&rule); err != nil {
		ctx.JSON(http.StatusBadRequest, common.NewResponseWithError(err))
		return
	}

	rule.Id = ctx.Param("rule_id")

	if err := c.RuleService.UpdateRule(ctx.Request.Context(), rule); err != nil {
		ctx.JSON(http.StatusInternalServerError, common.NewResponseWithError(err))
		return
	}

	ctx.JSON(http.StatusOK, common.NewResponseSuccess(rule))
}

func (c *RuleController) DeleteRule(ctx *gin.Context) {
	ruleId := ctx.Param("rule_id")

	if err := c.RuleService.DeleteRule(ctx.Request.Context(), ruleId); err != nil {
		ctx.JSON(http.StatusInternalServerError, common.NewResponseWithError(err))
		return
	}

	ctx.JSON(http.StatusOK, common.NewResponseSuccess[any](nil))
}
