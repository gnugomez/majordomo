// electron-squirrel-startup ships no types and has no @types package.
declare module "electron-squirrel-startup" {
  /** True when the process was launched by a Squirrel.Windows install/
   * update/uninstall event that the module already handled — the app must
   * quit immediately. Always false outside Windows. */
  const handledSquirrelEvent: boolean;
  export = handledSquirrelEvent;
}
