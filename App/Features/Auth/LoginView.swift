import BuctModel
import BuctSync
import SwiftUI
import UIKit

enum LoginTargetKind: String, CaseIterable {
    case undergrad = "本科生 (统一身份认证)"
    case graduate = "研究生 (GMIS)"
}

struct LoginView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var targetKind: LoginTargetKind = .undergrad
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var rememberCredential: Bool = true
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    // 图形验证码（本科 & 研究生共用）
    @State private var captchaImageData: Data?
    @State private var captchaCode: String = ""
    @State private var needsUndergradCaptcha: Bool = false

    // 短信二次验证（本科 sidportal）
    @State private var needsSecondarySms: Bool = false
    @State private var maskedPhone: String = ""
    @State private var smsImgCaptchaData: Data?
    @State private var smsImgCaptchaCode: String = ""
    @State private var smsCode: String = ""
    @State private var trustDevice: Bool = true
    @State private var smsCountdown: Int = 0
    @State private var hasPasskeyForUser: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                BuctBackdropBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        Picker("身份类型", selection: $targetKind) {
                            ForEach(LoginTargetKind.allCases, id: \.self) { kind in
                                Text(kind.rawValue).tag(kind)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: targetKind) { _, newValue in
                            resetChallengeState()
                            if newValue == .graduate {
                                Task { await loadGraduateCaptcha() }
                            }
                        }

                        if needsSecondarySms {
                            secondarySmsCard
                        } else {
                            credentialsCard
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                        }

                        Button {
                            Task {
                                await environment.enterDemoMode()
                                dismiss()
                            }
                        } label: {
                            Text("跳过登录，一键体验演示数据")
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.glass)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("登录北化一站")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
            .task {
                if let saved = await environment.syncService.loadSavedCredential() {
                    username = saved.username
                    password = saved.password
                    hasPasskeyForUser = await environment.syncService.hasPasskey(username: saved.username)
                }
            }
            .onChange(of: username) { _, newVal in
                let clean = newVal.trimmingCharacters(in: .whitespacesAndNewlines)
                Task {
                    hasPasskeyForUser = await environment.syncService.hasPasskey(username: clean)
                }
            }
        }
    }

    private var credentialsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("学号", text: $username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            SecureField(targetKind == .undergrad ? "统一身份认证密码" : "研究生系统密码", text: $password)
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            if targetKind == .undergrad {
                Toggle("使用 Keychain 加密记住密码（用于会话自动续期）", isOn: $rememberCredential)
                    .font(.caption)
            } else {
                Text("提示：校外网络下将自动经 WebVPN 访问 gmis.buct.edu.cn。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if (targetKind == .graduate || needsUndergradCaptcha), let imgData = captchaImageData, let uiImg = UIImage(data: imgData) {
                HStack(spacing: 12) {
                    TextField("图形验证码", text: $captchaCode)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Button {
                        Task {
                            if targetKind == .graduate {
                                await loadGraduateCaptcha()
                            } else if let refreshed = await environment.syncService.refreshUndergradCaptcha() {
                                captchaImageData = refreshed
                            }
                        }
                    } label: {
                        Image(uiImage: uiImg)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 110, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                Task { await handlePrimaryLogin() }
            } label: {
                HStack {
                    if isLoading { ProgressView().tint(.white) }
                    Text(needsUndergradCaptcha ? "提交验证码登录" : "登录")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.glassProminent)
            .disabled(isLoading || username.isEmpty || password.isEmpty)

            if targetKind == .undergrad && hasPasskeyForUser {
                Button {
                    Task { await handlePasskeyLogin() }
                } label: {
                    Label("使用 Face ID 通行密钥一键登录", systemImage: "faceid")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glass)
                .disabled(isLoading)
            }
        }
        .padding(16)
        .buctGlassCard(cornerRadius: 22, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
    }

    private var secondarySmsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("短信二次验证")
                .font(.headline)
            Text(maskedPhone.isEmpty ? "当前登录触发统一认证风控，请完成短信验证" : "已绑定手机：\(maskedPhone)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let data = smsImgCaptchaData, let uiImg = UIImage(data: data) {
                HStack(spacing: 12) {
                    TextField("发短信前图形码", text: $smsImgCaptchaCode)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Button {
                        Task { await loadSecondarySmsCaptcha() }
                    } label: {
                        Image(uiImage: uiImg)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 110, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    Task { await sendSecondarySms() }
                } label: {
                    Text(smsCountdown > 0 ? "重新发送 (\(smsCountdown)s)" : "发送短信验证码")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .disabled(smsCountdown > 0 || smsImgCaptchaCode.isEmpty || isLoading)
            }

            TextField("短信验证码", text: $smsCode)
                .keyboardType(.numberPad)
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Toggle("记住当前设备（下次免短信）", isOn: $trustDevice)
                .font(.caption)

            HStack(spacing: 10) {
                Button("返回") {
                    resetChallengeState()
                }
                .buttonStyle(.glass)

                Button {
                    Task { await verifySecondarySms() }
                } label: {
                    if isLoading { ProgressView().tint(.white) }
                    Text("验证并登录")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .disabled(smsCode.count < 4 || isLoading)
            }
        }
        .padding(16)
        .buctGlassCard(cornerRadius: 22, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
    }

    private func handlePrimaryLogin() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        if targetKind == .graduate {
            let result = await environment.syncService.loginGraduate(
                username: username,
                password: password,
                captcha: captchaCode
            )
            switch result {
            case .success(let profile):
                await environment.completeLogin(profile: profile)
                dismiss()
            case .failure(let err):
                errorMessage = err.localizedDescription
                await loadGraduateCaptcha()
            }
            return
        }

        let state: LoginFlowState
        if needsUndergradCaptcha {
            state = await environment.syncService.submitUndergradCaptcha(
                captchaCode,
                username: username,
                password: password,
                saveCredential: rememberCredential
            )
        } else {
            state = await environment.syncService.loginUndergrad(
                username: username,
                password: password,
                saveCredential: rememberCredential
            )
        }
        await applyUndergradFlowState(state)
    }

    private func handlePasskeyLogin() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let state = await environment.syncService.loginWithPasskey(username: username)
        await applyUndergradFlowState(state)
    }

    private func applyUndergradFlowState(_ state: LoginFlowState) async {
        switch state {
        case .authenticated(let profile):
            await environment.completeLogin(profile: profile)
            dismiss()
        case .captchaRequired(let data, let msg):
            needsUndergradCaptcha = true
            captchaImageData = data
            captchaCode = ""
            errorMessage = msg
        case .secondarySmsRequired(let phone):
            needsSecondarySms = true
            maskedPhone = phone
            errorMessage = nil
            await loadSecondarySmsCaptcha()
        case .invalidCredentials:
            errorMessage = "学号或密码错误，请重新检查"
        case .failure(let msg):
            errorMessage = msg
        }
    }

    private func loadGraduateCaptcha() async {
        do {
            captchaImageData = try await environment.syncService.fetchGmisChallenge()
            captchaCode = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadSecondarySmsCaptcha() async {
        let res = await environment.syncService.prepareSecondarySmsCaptcha()
        switch res {
        case .success(let data):
            smsImgCaptchaData = data
            smsImgCaptchaCode = ""
        case .failure(let err):
            errorMessage = err.localizedDescription
        }
    }

    private func sendSecondarySms() async {
        isLoading = true
        defer { isLoading = false }
        let res = await environment.syncService.sendSecondarySmsCode(captchaCode: smsImgCaptchaCode)
        switch res {
        case .success(let seconds):
            errorMessage = nil
            startCountdown(seconds)
        case .failure(let err):
            errorMessage = err.localizedDescription
            await loadSecondarySmsCaptcha()
        }
    }

    private func verifySecondarySms() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let state = await environment.syncService.submitSecondarySmsCode(
            smsCode: smsCode,
            rememberDevice: trustDevice,
            username: username,
            password: password,
            saveCredential: rememberCredential
        )
        await applyUndergradFlowState(state)
    }

    private func startCountdown(_ seconds: Int) {
        smsCountdown = seconds
        Task {
            while smsCountdown > 0 {
                try? await Task.sleep(for: .seconds(1))
                if smsCountdown > 0 { smsCountdown -= 1 }
            }
        }
    }

    private func resetChallengeState() {
        errorMessage = nil
        captchaImageData = nil
        captchaCode = ""
        needsUndergradCaptcha = false
        needsSecondarySms = false
        smsImgCaptchaData = nil
        smsImgCaptchaCode = ""
        smsCode = ""
        smsCountdown = 0
    }
}
