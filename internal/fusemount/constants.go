package fusemount

import "os"

var MountRoot = func() string {
	if v := os.Getenv("LITEPAN_MOUNT_DIR"); v != "" {
		return v
	}
	return "/storage/videos/mount"
}()

const (
	KeyEnabled           = "fuse_enabled"
	DefaultEntryTimeoutS = 30
	DefaultAttrTimeoutS  = 3
)
