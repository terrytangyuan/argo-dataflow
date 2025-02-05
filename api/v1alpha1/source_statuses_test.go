package v1alpha1

import (
	"errors"
	"strings"
	"testing"

	"k8s.io/apimachinery/pkg/api/resource"

	"github.com/stretchr/testify/assert"
)

func TestSourceStatuses_Set(t *testing.T) {
	ss := SourceStatuses{}

	ss.IncrTotal("bar", 1, strings.Repeat("x", 33), resource.MustParse("1"))

	if assert.Len(t, ss, 1) {
		s := ss["bar"]
		if assert.NotNil(t, s.LastMessage) {
			assert.NotEmpty(t, s.LastMessage.Data)
		}
		if assert.Len(t, s.Metrics, 1) {
			assert.Equal(t, uint64(1), s.Metrics["1"].Total)
			assert.Equal(t, resource.MustParse("1"), s.Metrics["1"].Rate)
		}
	}

	ss.IncrTotal("bar", 1, "bar", resource.MustParse("1"))

	if assert.Len(t, ss, 1) {
		s := ss["bar"]
		if assert.NotNil(t, s.LastMessage) {
			assert.Equal(t, "bar", s.LastMessage.Data)
		}
		if assert.Len(t, s.Metrics, 1) {
			assert.Equal(t, uint64(2), s.Metrics["1"].Total)
			assert.Equal(t, resource.MustParse("1"), s.Metrics["1"].Rate)
		}
	}

	ss.IncrTotal("bar", 0, "foo", resource.MustParse("1"))

	if assert.Len(t, ss, 1) {
		s := ss["bar"]
		if assert.NotNil(t, s.LastMessage) {
			assert.Equal(t, "foo", s.LastMessage.Data)
		}
		if assert.Len(t, s.Metrics, 2) {
			assert.Equal(t, uint64(1), s.Metrics["0"].Total)
			assert.Equal(t, uint64(2), s.Metrics["1"].Total)
		}
	}

	ss.IncrTotal("baz", 0, "foo", resource.MustParse("1"))

	if assert.Len(t, ss, 2) {
		s := ss["baz"]
		if assert.NotNil(t, s.LastMessage) {
			assert.Equal(t, "foo", s.LastMessage.Data)
		}
		if assert.Len(t, s.Metrics, 1) {
			assert.Equal(t, uint64(1), s.Metrics["0"].Total)
		}
	}
}

func TestSourceStatuses_IncErrors(t *testing.T) {
	ss := SourceStatuses{}
	err := errors.New(strings.Repeat("x", 33))
	ss.IncrErrors("foo", 0, err)
	assert.Equal(t, uint64(1), ss["foo"].Metrics["0"].Errors)
	assert.NotEmpty(t, ss["foo"].LastError.Message)
	assert.NotEmpty(t, ss["foo"].LastError.Time)
	ss.IncrErrors("foo", 0, err)
	assert.Equal(t, uint64(2), ss["foo"].Metrics["0"].Errors)
	ss.IncrErrors("bar", 0, err)
	assert.Equal(t, uint64(1), ss["bar"].Metrics["0"].Errors)
}

func TestSourceStatuses_SetPending(t *testing.T) {
	ss := SourceStatuses{}

	ss.SetPending("bar", 23)

	if assert.Len(t, ss, 1) {
		assert.Equal(t, uint64(23), *ss["bar"].Pending)
	}

	ss.SetPending("bar", 34)

	if assert.Len(t, ss, 1) {
		assert.Equal(t, uint64(34), *ss["bar"].Pending)
	}

	ss.SetPending("bar", 45)

	if assert.Len(t, ss, 1) {
		assert.Equal(t, uint64(45), *ss["bar"].Pending)
	}
}

func TestSourceStatus_GetPending(t *testing.T) {
	assert.Equal(t, uint64(0), SourceStatuses{}.GetPending())
	v := uint64(1)
	assert.Equal(t, uint64(1), SourceStatuses{"0": {Pending: &v}}.GetPending())
}

func TestSourceStatus_AnyErrors(t *testing.T) {
	assert.False(t, SourceStatuses{}.AnyErrors())
	assert.True(t, SourceStatuses{"0": {Metrics: map[string]Metrics{"0": {Errors: 1}}}}.AnyErrors())
}
