package main

import (
	"context"
	"log"
	"slices"
	"strconv"

	"github.com/ClickHouse/clickhouse-go/v2"
	"github.com/ClickHouse/clickhouse-go/v2/lib/driver"
	"github.com/gin-gonic/gin"
)

var conn driver.Conn

var columns = []string{
	"src_addr",
	"dst_addr",
	"src_port",
	"dst_port",
	"etype",
	"proto",
	"tcp_flags",
	"sampler_address",
}

func GetTop(c *gin.Context) {
	column := c.Query("column")
	if column == "" {
		c.JSON(400, gin.H{"error": "column parameter is required"})
		return
	}
	if slices.Contains(columns, column) == false {
		c.JSON(400, gin.H{"error": "invalid column parameter"})
		return
	}

	k := c.Query("k")
	if _, err := strconv.Atoi(k); err != nil && k != "" {
		c.JSON(400, gin.H{"error": "k parameter must be a valid integer or empty"})
		return
	}

	chCtx := clickhouse.Context(context.Background(), clickhouse.WithParameters(clickhouse.Parameters{
		"column": column,
		"k":      k,
	}))

	var query string

	if k == "" {
		query = `
		WITH top AS (
			SELECT {column:Identifier} AS column, sum(bytes) AS bytes
			FROM flows_raw
			GROUP BY column
			ORDER BY bytes DESC
		)
		SELECT toString(column) AS column, bytes
		FROM top
		`
	} else {
		query = `
		WITH top_k AS (
			SELECT arrayJoin(approx_top_sum({k:UInt32})({column:Identifier}, bytes)) AS i
			FROM flows_raw
		)
		SELECT toString(i.1) AS column, i.2 AS bytes
		FROM top_k
		`
	}

	rows, err := conn.Query(chCtx, query)
	if err != nil {
		c.Error(err)
		return
	}
	defer rows.Close()

	var results []struct {
		Column string `ch:"column"`
		Bytes  uint64 `ch:"bytes"`
	}
	for rows.Next() {
		var result struct {
			Column string `ch:"column"`
			Bytes  uint64 `ch:"bytes"`
		}
		if err := rows.Scan(&result.Column, &result.Bytes); err != nil {
			c.Error(err)
			return
		}
		results = append(results, result)
	}
	if err := rows.Err(); err != nil {
		c.Error(err)
		return
	}
	c.JSON(200, results)
}

func main() {
	var err error

	conn, err = clickhouse.Open(&clickhouse.Options{
		Addr: []string{"localhost:9000"},
		Auth: clickhouse.Auth{
			Database: "default",
			Username: "default",
			Password: "password",
		},
		TLS: nil,
	})
	if err != nil {
		log.Fatal(err)
	}
	defer conn.Close()

	if err := conn.Ping(context.Background()); err != nil {
		log.Fatal(err)
	}

	router := gin.Default()
	router.GET("/top", GetTop)
	router.Run(":8090")
}
