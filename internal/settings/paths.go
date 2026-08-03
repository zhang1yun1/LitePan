package settings

import (
	"os"
	"path/filepath"
	"strings"
)

const (
	KeyMountRootDir       = "mount_root_dir"
	KeyStrmDir            = "strm_dir"
	KeyFuseReadCacheDir   = "fuse_read_cache_dir"

	DefaultMountRootDir     = "/storage/videos/mount"
	DefaultStrmDir          = "/storage/videos/strm"
	DefaultFuseReadCacheDir = "/storage/videos/fuse_cache"
)

// normalizePath 校验并规范化路径，若不是绝对路径则保持现状或尝试规范化，并自动创建目录。
func normalizePath(raw, fallback string) string {
	val := strings.TrimSpace(raw)
	if val == "" {
		val = fallback
	}
	val = filepath.Clean(val)
	// 尝试自动创建目录，避免路径不存在导致运行错误
	_ = os.MkdirAll(val, 0755)
	return val
}

// defaultMountRootDir 获取挂载根目录默认值（环境变量 > CoreELEC 默认）
func defaultMountRootDir() string {
	if v := strings.TrimSpace(os.Getenv("LITEPAN_MOUNT_DIR")); v != "" {
		return v
	}
	return DefaultMountRootDir
}

// defaultStrmDir 获取 STRM 输出目录默认值（环境变量 > CoreELEC 默认）
func defaultStrmDir() string {
	if v := strings.TrimSpace(os.Getenv("LITEPAN_STRM_DIR")); v != "" {
		return v
	}
	return DefaultStrmDir
}

// defaultFuseReadCacheDir 获取 FUSE 读缓存目录默认值（环境变量 > CoreELEC 默认）
func defaultFuseReadCacheDir() string {
	if v := strings.TrimSpace(os.Getenv("LITEPAN_FUSE_CACHE_DIR")); v != "" {
		return v
	}
	return DefaultFuseReadCacheDir
}

// pathsSpecs 返回存储路径分类下的全局设置规格定义。
func pathsSpecs() []Spec {
	return []Spec{
		{
			Key:         KeyMountRootDir,
			Type:        TypeString,
			Category:    "paths",
			Label:       "本地挂载根目录",
			Description: "云盘本地 FUSE 挂载点根路径。修改后对新建立的挂载点生效；旧挂载点文件建议手动搬迁。",
			Default:     defaultMountRootDir(),
			normalize: func(v string) string {
				return normalizePath(v, defaultMountRootDir())
			},
		},
		{
			Key:         KeyStrmDir,
			Type:        TypeString,
			Category:    "paths",
			Label:       "STRM 存放目录",
			Description: "STRM 视频快捷方式文件的默认输出目录。新任务同步与刮削将写入此位置。",
			Default:     defaultStrmDir(),
			normalize: func(v string) string {
				return normalizePath(v, defaultStrmDir())
			},
		},
		{
			Key:         KeyFuseReadCacheDir,
			Type:        TypeString,
			Category:    "paths",
			Label:       "FUSE 读缓存目录",
			Description: "FUSE 本地读块数据临时缓存存储目录。",
			Default:     defaultFuseReadCacheDir(),
			normalize: func(v string) string {
				return normalizePath(v, defaultFuseReadCacheDir())
			},
		},
	}
}

// MountRootDir 获取当前生效的本地挂载根目录。
func (s *Service) MountRootDir() string {
	if v, ok := s.raw(KeyMountRootDir); ok && strings.TrimSpace(v) != "" {
		return normalizePath(v, defaultMountRootDir())
	}
	if env := strings.TrimSpace(os.Getenv("LITEPAN_MOUNT_DIR")); env != "" {
		return normalizePath(env, DefaultMountRootDir)
	}
	return DefaultMountRootDir
}

// StrmDir 获取当前生效的 STRM 存放目录。
func (s *Service) StrmDir() string {
	if v, ok := s.raw(KeyStrmDir); ok && strings.TrimSpace(v) != "" {
		return normalizePath(v, defaultStrmDir())
	}
	if env := strings.TrimSpace(os.Getenv("LITEPAN_STRM_DIR")); env != "" {
		return normalizePath(env, DefaultStrmDir)
	}
	return DefaultStrmDir
}

// FuseReadCacheDir 获取当前生效的 FUSE 读缓存目录。若未主动配置且无环境变量，则返回空让调用方回落到数据目录。
func (s *Service) FuseReadCacheDir() string {
	if v, ok := s.raw(KeyFuseReadCacheDir); ok && strings.TrimSpace(v) != "" {
		return normalizePath(v, defaultFuseReadCacheDir())
	}
	if env := strings.TrimSpace(os.Getenv("LITEPAN_FUSE_CACHE_DIR")); env != "" {
		return normalizePath(env, DefaultFuseReadCacheDir)
	}
	return ""
}
