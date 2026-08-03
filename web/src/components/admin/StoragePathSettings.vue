<script setup lang="ts">
import { computed, onMounted, reactive, ref } from "vue";
import { getApiErrorMessage } from "@/api/client";
import {
  fetchSettings,
  saveSettings,
  type SettingItem,
} from "@/api/settings";
import { toast } from "@/composables/useToast";
import { useSettingsLoad } from "@/composables/useSettingsLoad";
import { useAdminPageLoading } from "@/composables/useAdminLoadingBar";
import { useSettingsPageDirty } from "@/composables/useSettingsPageDirty";
import AppButton from "@/components/base/AppButton.vue";
import AppInput from "@/components/base/AppInput.vue";
import SettingsCard from "@/components/admin/SettingsCard.vue";
import SettingsRow from "@/components/admin/SettingsRow.vue";
import SettingsHelpTooltip from "@/components/admin/SettingsHelpTooltip.vue";
import "@/styles/admin-shared.css";

const { loading, runLoad } = useSettingsLoad();
useAdminPageLoading("paths", loading);

const saving = ref(false);
const items = ref<SettingItem[]>([]);
const form = reactive<Record<string, string>>({});
const original = reactive<Record<string, string>>({});

const accentColor = "var(--brand)";

const pathItems = computed(() => items.value.filter((it) => it.category === "paths"));

function isChanged(item: SettingItem): boolean {
  return (form[item.key] ?? "") !== (original[item.key] ?? "");
}

const changedKeys = computed(() => pathItems.value.filter((it) => isChanged(it)).map((it) => it.key));
const isDirty = computed(() => changedKeys.value.length > 0);

function revertDraft() {
  for (const it of pathItems.value) {
    form[it.key] = original[it.key];
  }
}

useSettingsPageDirty(isDirty, revertDraft);

function applyPayload(payload: { items: SettingItem[] }) {
  items.value = payload.items || [];
  for (const it of pathItems.value) {
    form[it.key] = it.value;
    original[it.key] = it.value;
  }
}

async function load() {
  await runLoad(async () => {
    applyPayload(await fetchSettings());
  }, "加载存储路径设置失败");
}

onMounted(load);

async function save() {
  if (!isDirty.value) return;
  saving.value = true;
  try {
    const changed: Record<string, string> = {};
    for (const key of changedKeys.value) {
      changed[key] = form[key];
    }
    if (Object.keys(changed).length > 0) {
      applyPayload(await saveSettings(changed));
    }
    toast.success("存储路径设置已保存");
  } catch (e) {
    toast.error(getApiErrorMessage(e, "保存失败"));
  } finally {
    saving.value = false;
  }
}
</script>

<template>
  <div class="storage-paths-settings">
    <div class="page-toolbar">
      <div class="page-toolbar__title">
        <h2>存储路径设置</h2>
        <p class="page-toolbar__desc">管理云盘本地挂载根目录、STRM 存放目录及 FUSE 读缓存存储路径。</p>
      </div>
      <div class="page-toolbar__actions">
        <AppButton
          type="button"
          variant="primary"
          :disabled="!isDirty || saving"
          @click="save"
        >
          {{ saving ? "保存中…" : "保存改动" }}
        </AppButton>
      </div>
    </div>

    <template v-if="!loading">
      <SettingsCard title="核心存储与输出路径" :accent="accentColor">
        <SettingsRow
          v-for="it in pathItems"
          :key="it.key"
          :show-changed-badge="true"
          :changed="isChanged(it)"
        >
          <template #info>
            <div class="settings-row__label">
              <span>{{ it.label || it.key }}</span>
              <SettingsHelpTooltip
                v-if="it.description"
                :title="`${it.label || it.key}说明`"
              >
                <p>{{ it.description }}</p>
                <p>修改保存后，新生成/挂载的文件将使用新路径。旧物理文件请根据需要手动迁移。</p>
              </SettingsHelpTooltip>
            </div>
          </template>
          <template #control>
            <div class="settings-row__field">
              <div class="field-text">
                <AppInput v-model="form[it.key]" :placeholder="it.default" autocomplete="off" />
              </div>
            </div>
          </template>
        </SettingsRow>
      </SettingsCard>
    </template>
  </div>
</template>

<style scoped>
.storage-paths-settings {
  padding-bottom: 24px;
}

.page-toolbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 20px;
}

.page-toolbar__title h2 {
  margin: 0 0 4px 0;
  font-size: 20px;
  font-weight: 600;
  color: var(--text-main, #111827);
}

.page-toolbar__desc {
  margin: 0;
  font-size: 13px;
  color: var(--text-muted, #6b7280);
}

.page-toolbar__actions {
  display: flex;
  gap: 12px;
}
</style>
