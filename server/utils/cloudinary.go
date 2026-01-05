package utils

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/cloudinary/cloudinary-go/v2"
	"github.com/cloudinary/cloudinary-go/v2/api/uploader"
)

var CloudinaryClient *cloudinary.Cloudinary

func InitCloudinary() error {
	cloudinaryURL := os.Getenv("CLOUDINARY_URL")
	if cloudinaryURL == "" {
		return fmt.Errorf("CLOUDINARY_URL not set in environment")
	}

	var err error
	CloudinaryClient, err = cloudinary.NewFromURL(cloudinaryURL)
	if err != nil {
		return fmt.Errorf("failed to initialize Cloudinary: %v", err)
	}

	return nil
}

func UploadProfilePicFromURL(imageURL, userID string) (string, error) {
	if imageURL == "" {
		return "", nil
	}

	if CloudinaryClient == nil {
		return "", fmt.Errorf("cloudinary not initialized")
	}

	resp, err := http.Get(imageURL)
	if err != nil {
		return "", fmt.Errorf("failed to download image: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("failed to download image: status %d", resp.StatusCode)
	}

	imageData, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("failed to read image data: %v", err)
	}

	return uploadToCloudinary(imageData, userID)
}

func UploadProfilePicToCloudinary(imageData []byte, userID string) (string, error) {
	if CloudinaryClient == nil {
		return "", fmt.Errorf("cloudinary not initialized")
	}

	return uploadToCloudinary(imageData, userID)
}

func uploadToCloudinary(imageData []byte, userID string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	publicID := fmt.Sprintf("user_%s_%d", userID, time.Now().Unix())
	overwrite := false

	reader := bytes.NewReader(imageData)

	uploadResult, err := CloudinaryClient.Upload.Upload(ctx, reader, uploader.UploadParams{
		Folder:         "voxarena/profile-pics",
		PublicID:       publicID,
		ResourceType:   "image",
		Overwrite:      &overwrite,
		Transformation: "c_fill,g_face,h_400,w_400",
	})

	if err != nil {
		return "", fmt.Errorf("cloudinary upload failed: %v", err)
	}

	return uploadResult.SecureURL, nil
}

func UploadAudioToCloudinary(audioData []byte, userID string) (string, error) {
	if CloudinaryClient == nil {
		return "", fmt.Errorf("cloudinary not initialized")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	publicID := fmt.Sprintf("audio_%s_%d", userID, time.Now().Unix())
	overwrite := false

	reader := bytes.NewReader(audioData)

	uploadResult, err := CloudinaryClient.Upload.Upload(ctx, reader, uploader.UploadParams{
		Folder:       "voxarena/audio-files",
		PublicID:     publicID,
		ResourceType: "video",
		Overwrite:    &overwrite,
	})

	if err != nil {
		return "", fmt.Errorf("cloudinary upload failed: %v", err)
	}

	return uploadResult.SecureURL, nil
}

func UploadThumbnailToCloudinary(imageData []byte, userID string) (string, error) {
	if CloudinaryClient == nil {
		return "", fmt.Errorf("cloudinary not initialized")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	publicID := fmt.Sprintf("thumbnail_%s_%d", userID, time.Now().Unix())
	overwrite := false

	reader := bytes.NewReader(imageData)

	uploadResult, err := CloudinaryClient.Upload.Upload(ctx, reader, uploader.UploadParams{
		Folder:         "voxarena/thumbnails",
		PublicID:       publicID,
		ResourceType:   "image",
		Overwrite:      &overwrite,
		Transformation: "c_fill,h_600,w_800",
	})

	if err != nil {
		return "", fmt.Errorf("cloudinary upload failed: %v", err)
	}

	return uploadResult.SecureURL, nil
}

func UploadCommunityImageToCloudinary(imageData []byte, userID string) (string, error) {
	if CloudinaryClient == nil {
		return "", fmt.Errorf("cloudinary not initialized")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	publicID := fmt.Sprintf("community_%s_%d", userID, time.Now().Unix())
	overwrite := false

	reader := bytes.NewReader(imageData)

	uploadResult, err := CloudinaryClient.Upload.Upload(ctx, reader, uploader.UploadParams{
		Folder:         "voxarena/community-images",
		PublicID:       publicID,
		ResourceType:   "image",
		Overwrite:      &overwrite,
		Transformation: "c_fill,h_1080,w_1080,q_auto",
	})

	if err != nil {
		return "", fmt.Errorf("cloudinary upload failed: %v", err)
	}

	return uploadResult.SecureURL, nil
}

func UploadCommunityAudioToCloudinary(audioData []byte, userID string) (string, error) {
	if CloudinaryClient == nil {
		return "", fmt.Errorf("cloudinary not initialized")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	publicID := fmt.Sprintf("community_audio_%s_%d", userID, time.Now().Unix())
	overwrite := false

	reader := bytes.NewReader(audioData)

	uploadResult, err := CloudinaryClient.Upload.Upload(ctx, reader, uploader.UploadParams{
		Folder:       "voxarena/community-audio",
		PublicID:     publicID,
		ResourceType: "video",
		Overwrite:    &overwrite,
	})

	if err != nil {
		return "", fmt.Errorf("cloudinary upload failed: %v", err)
	}

	return uploadResult.SecureURL, nil
}

func extractPublicID(url string) string {
	parts := strings.Split(url, "/upload/")
	if len(parts) < 2 {
		return ""
	}

	pathParts := strings.Split(parts[1], "/")
	if len(pathParts) < 2 {
		return ""
	}

	startIdx := 1
	if strings.HasPrefix(pathParts[1], "v") {
		startIdx = 2
	}

	publicIDParts := pathParts[startIdx:]
	publicID := strings.Join(publicIDParts, "/")

	if dotIdx := strings.LastIndex(publicID, "."); dotIdx != -1 {
		publicID = publicID[:dotIdx]
	}

	return publicID
}

func DeleteCommunityImageFromCloudinary(imageURL string) error {
	if CloudinaryClient == nil {
		return fmt.Errorf("cloudinary not initialized")
	}

	if imageURL == "" {
		return nil
	}

	publicID := extractPublicID(imageURL)
	if publicID == "" {
		return fmt.Errorf("failed to extract public ID from URL: %s", imageURL)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	_, err := CloudinaryClient.Upload.Destroy(ctx, uploader.DestroyParams{
		PublicID:     publicID,
		ResourceType: "image",
	})

	if err != nil {
		return fmt.Errorf("failed to delete image from cloudinary: %v", err)
	}

	return nil
}

func DeleteCommunityAudioFromCloudinary(audioURL string) error {
	if CloudinaryClient == nil {
		return fmt.Errorf("cloudinary not initialized")
	}

	if audioURL == "" {
		return nil
	}

	publicID := extractPublicID(audioURL)
	if publicID == "" {
		return fmt.Errorf("failed to extract public ID from URL: %s", audioURL)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	_, err := CloudinaryClient.Upload.Destroy(ctx, uploader.DestroyParams{
		PublicID:     publicID,
		ResourceType: "video",
	})

	if err != nil {
		return fmt.Errorf("failed to delete audio from cloudinary: %v", err)
	}

	return nil
}
