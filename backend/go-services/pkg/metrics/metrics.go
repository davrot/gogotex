package metrics

import (
	"github.com/prometheus/client_golang/prometheus"
)

var (
	RateLimitAllowed = prometheus.NewCounterVec(
		prometheus.CounterOpts{Namespace: "gogotex", Name: "rate_limit_allowed_total", Help: "Number of allowed requests by limiter type."},
		[]string{"limiter"},
	)
	RateLimitRejected = prometheus.NewCounterVec(
		prometheus.CounterOpts{Namespace: "gogotex", Name: "rate_limit_rejected_total", Help: "Number of rejected requests by limiter type."},
		[]string{"limiter"},
	)
)

func RegisterCollectors(reg prometheus.Registerer) {
	reg.MustRegister(RateLimitAllowed)
	reg.MustRegister(RateLimitRejected)
}
