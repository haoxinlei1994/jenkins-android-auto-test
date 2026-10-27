import hudson.security.FullControlOnceLoggedInAuthorizationStrategy
import hudson.security.HudsonPrivateSecurityRealm
import hudson.security.SecurityRealm
import jenkins.model.Jenkins

def username = System.getenv('JENKINS_ADMIN_USER')
def password = System.getenv('JENKINS_ADMIN_PASSWORD')

if (!username || !password) {
    println '[init] 未配置 JENKINS_ADMIN_USER / JENKINS_ADMIN_PASSWORD，跳过管理员初始化。'
} else {
    def instance = Jenkins.get()

    if (instance.getSecurityRealm() != SecurityRealm.NO_AUTHENTICATION) {
        println '[init] Jenkins 已配置安全域，跳过管理员初始化。'
    } else {
        def realm = new HudsonPrivateSecurityRealm(false)
        realm.createAccount(username, password)
        instance.setSecurityRealm(realm)

        def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
        strategy.setDenyAnonymousReadAccess(true)
        instance.setAuthorizationStrategy(strategy)
        instance.save()

        println "[init] 已创建 Jenkins 管理员: ${username}"
    }
}
