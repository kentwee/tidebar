namespace Tidebar.Modules {
    public interface IHudModule {
        string Id { get; }           // 对应 config.ini 里的开关名
        int IntervalSeconds { get; } // 多久采一次
        bool Available { get; }      // 本机能不能用（比如没 N 卡、没装 Syncthing）
        void Collect();              // 后台线程调用，只更新自己的缓存字段
    }
}
