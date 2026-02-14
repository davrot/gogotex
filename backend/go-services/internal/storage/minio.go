package storage

import (
	"context"
	"fmt"
	"io"
	"time"

	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
	"net/url"
)

// MinIOStorage is a thin wrapper around the minio client used by services.
type MinIOStorage struct {
	client *minio.Client
	bucket string
}

// NewMinIOStorage creates a new MinIO storage client and ensures the bucket exists.
func NewMinIOStorage(cfg *MinIOConfig) (*MinIOStorage, error) {
	if cfg == nil || cfg.Endpoint == "" {
		return nil, fmt.Errorf("minio config missing")
	}
	mc, err := minio.New(cfg.Endpoint, &minio.Options{
		Creds:  credentials.NewStaticV4(cfg.AccessKey, cfg.SecretKey, ""),
		Secure: cfg.UseSSL,
	})
	if err != nil {
		return nil, fmt.Errorf("minio new: %w", err)
	}
	s := &MinIOStorage{client: mc, bucket: cfg.Bucket}
	// ensure bucket exists (idempotent)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := mc.MakeBucket(ctx, s.bucket, minio.MakeBucketOptions{}); err != nil {
		// ignore "already exists" style errors
		exist, xerr := mc.BucketExists(ctx, s.bucket)
		if xerr != nil || !exist {
			return nil, fmt.Errorf("minio bucket ensure: %w", err)
		}
	}
	return s, nil
}

// UploadFile uploads data from reader to the configured bucket using the provided key.
func (s *MinIOStorage) UploadFile(ctx context.Context, key string, reader io.Reader, size int64, contentType string) error {
	_, err := s.client.PutObject(ctx, s.bucket, key, reader, size, minio.PutObjectOptions{ContentType: contentType})
	return err
}

// DownloadFile returns a ReadCloser for the stored object.
func (s *MinIOStorage) DownloadFile(ctx context.Context, key string) (io.ReadCloser, error) {
	obj, err := s.client.GetObject(ctx, s.bucket, key, minio.GetObjectOptions{})
	if err != nil {
		return nil, err
	}
	// perform a stat to ensure object exists
	if _, err := obj.Stat(); err != nil {
		obj.Close()
		return nil, err
	}
	return obj, nil
}

// GetPresignedURL returns a presigned GET URL valid for the given duration.
func (s *MinIOStorage) GetPresignedURL(ctx context.Context, key string, expires time.Duration) (string, error) {
	reqParams := make(url.Values)
	presigned, err := s.client.PresignedGetObject(ctx, s.bucket, key, expires, reqParams)
	if err != nil {
		return "", err
	}
	return presigned.String(), nil
}
