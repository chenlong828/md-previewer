// 组件间端口的注册表（L1a）：组件只在组合根装配时相互接线，彼此不 import。
// 这里是依赖倒置的落点——shared 只存注册与查询，不含任何实现。
const registry = new Map()

/** 组合根调用：注入一个端口实现（重复注入视为装配错误） */
export function provide(name, impl) {
    if (registry.has(name)) throw new Error(`port already provided: ${name}`)
    registry.set(name, impl)
}

/** 组件调用：取端口实现（未装配即抛错，不静默降级） */
export function use(name) {
    const impl = registry.get(name)
    if (!impl) throw new Error(`port not provided: ${name}`)
    return impl
}

/** 测试组合根用：清空端口表（产品路径不该调用） */
export function resetPorts() {
    registry.clear()
}

export function isProvided(name) {
    return registry.has(name)
}
