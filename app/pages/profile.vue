<template>
  <div class="min-h-screen bg-app-surface px-6 py-10">
    <div class="mx-auto max-w-4xl">
      <section class="panel-card p-6">
        <p class="text-xs uppercase tracking-[0.18em] text-app-muted">Profile</p>
        <h1 class="mt-2 text-2xl font-semibold text-app-text">个人中心</h1>
        <p class="mt-3 max-w-2xl text-sm leading-6 text-app-muted">
          这里预留为用户头像、昵称、角色、项目权限和通知偏好等个人信息管理入口。当前阶段先完成页面占位，便于 editor 头部跳转闭环。
        </p>

        <div class="mt-6 flex gap-3">
          <AppButton label="返回项目管理" icon="arrow" tone="primary" @click="navigateTo('/project')" />
          <AppButton label="系统设置" icon="settings" tone="neutral" @click="navigateTo('/settings')" />
        </div>
      </section>
    </div>
  </div>
</template>
