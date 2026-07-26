package net.simplyrin.discordvideo;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.File;
import java.io.FileReader;
import java.io.FileWriter;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.PrintWriter;
import java.io.StringWriter;
import java.net.MalformedURLException;
import java.net.URL;
import java.text.DecimalFormat;
import java.util.Optional;
import java.util.UUID;

import javax.net.ssl.HttpsURLConnection;

import org.apache.commons.io.FileUtils;
import org.apache.commons.io.FilenameUtils;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import javafx.application.Platform;
import javafx.beans.InvalidationListener;
import javafx.beans.binding.Bindings;
import javafx.event.ActionEvent;
import javafx.fxml.FXML;
import javafx.geometry.Insets;
import javafx.scene.Node;
import javafx.scene.control.Alert;
import javafx.scene.control.Alert.AlertType;
import javafx.scene.control.Button;
import javafx.scene.control.ButtonBar.ButtonData;
import javafx.scene.control.ButtonType;
import javafx.scene.control.Dialog;
import javafx.scene.control.Label;
import javafx.scene.control.PasswordField;
import javafx.scene.control.Separator;
import javafx.scene.control.Slider;
import javafx.scene.control.TextField;
import javafx.scene.control.ToolBar;
import javafx.scene.image.Image;
import javafx.scene.image.ImageView;
import javafx.scene.layout.GridPane;
import javafx.scene.media.Media;
import javafx.scene.media.MediaPlayer;
import javafx.scene.media.MediaView;
import javafx.stage.FileChooser;
import javafx.stage.Stage;
import javafx.util.Duration;
import javafx.util.Pair;
import lombok.AllArgsConstructor;
import lombok.Getter;
import net.simplyrin.httpclient.HttpClient;
import net.simplyrin.processmanager.ProcessManager;

/**
 * Created by SimplyRin on 2020/04/21.
 */
public class Controller {

	@FXML
	private Button button;
	@FXML
	private Button chooseButton;
	@FXML
	private Label fileName;
	@FXML
	private TextField textField;

	private File selectedFile;

	private int bitrate;
	private int currentVideoTime;
	private int filesize;

	public Controller() {
		controller = this;
	}

	@FXML
	private void onAction(ActionEvent event) {
		if (this.ffmpeg()) {
			return;
		}

		if (this.ffprobe()) {
			return;
		}

		try {
			if (this.textField.getText().equals("")) {
				this.textField.setText("8");
			}
			this.filesize = Integer.valueOf(this.textField.getText());
		} catch (Exception e) {
			this.buildAlert(AlertType.ERROR, "エラー", "構文エラー", "目標ファイルサイズには数値を入力してください。");
			return;
		}

		if (this.selectedFile != null) {
			TrimInfo trimInfo = this.item();

			if (trimInfo == null) {
				return;
			}

			runWithMainThread(() -> {
				button.setDisable(true);
				button.setText("処理中...");
			});

			Callback secondCallback = new Callback() {
				@Override
				public void response(String response) {
					System.out.println(response);
					if (response.startsWith("frame")) {
						String time = response.split("time=")[1].split(" ")[0];

						Time parsedTime = parseTime(time);
						int videoTime = parsedTime.totalSeconds();

						// System.out.println(response);

						double current = (double) videoTime / currentVideoTime * 100;

						runWithMainThread(() -> {
							String size;
							try {
								size = response.split("size=")[1].trim().split(" ")[0];
							} catch (Exception e) {
								size = response.split("Lsize=")[1].trim().split(" ")[0];
							}

							if (size.equals("0kB")) {
								button.setText("処理中...。時間がかかる場合があります...。");
							} else {
								button.setText("エンコード中: " + String.format("%.1f", current) + "% (" + size + ")");
							}
						});
					}
					if (response.equals("taskEnded")) {
						resetButton();
						try {
							Runtime.getRuntime().exec("explorer.exe /select," + latestOutput.getAbsolutePath());
						} catch (IOException e) {
							e.printStackTrace();
						}

						new Thread(new Runnable() {
							@Override
							public void run() {
								if (!questionnaire()) {
									return;
								}

								try {
									Thread.sleep(1000);
								} catch (Exception e) {
								}

								String size = formatFileSize(latestOutput.length());

								HttpClient httpClient = new HttpClient("https://api.simplyrin.net/App/DiscordVideo/enq.php?nocache=" + UUID.randomUUID().toString());
								httpClient.setData("bitrate=" + bitrate + "&targetFs=" + filesize + "%20MB&goalSize=" + size);
								httpClient.getResult();
							}
						}).start();
					}
				}
			};

			Callback firstCallback = new Callback() {
				@Override
				public void response(String response) {
					response = response.trim();
					if (response.startsWith("Duration:")) {
						// System.out.println(response);

						String time = response.split(" ")[1].split(" ")[0];

						int videoTime = 0;

						Time parsedTime = parseTime(time);
						videoTime += parsedTime.totalSeconds();
						// System.out.println("Video Time: " + videoTime + "s");
						if (trimInfo.bitrate != 0 && trimInfo.duration != 0) {
							videoTime = (int) trimInfo.getDuration();
						}

						currentVideoTime = videoTime;

						bitrate = setTimeSize(videoTime, filesize);
						// System.out.println("Target Bitrate: " + bitrate + " Kbps");
					}
					if (response.equals("taskEnded")) {
						String custom = "";
						if (trimInfo.bitrate != 0 && trimInfo.duration != 0) {
							custom += "-ss " + trimInfo.getStart() + " -to " + trimInfo.getEnd() + " ";
							bitrate = trimInfo.getBitrate();

							// System.out.println("---------------------------------");
							// System.out.println("Start: " + trimInfo.getStart());
							// System.out.println("End: " + trimInfo.getEnd());
							// System.out.println("Duration: " + trimInfo.getDuration());
							// System.out.println("Bitrate: " + bitrate);
							// System.out.println("---------------------------------");
						}

						if (bitrate <= 50) {
							// System.out.println("Capacity over");
							runWithMainThread(() -> {
								resetButton();
								buildAlert(AlertType.ERROR, "エラー！", "キャパオーバー！！！", "この動画を " + filesize + " MB 未満に変換することはできません。");
							});
							return;
						}

						// ここから ffmpeg -i input.mp4 -ss [duration] -t [duration] -c copy output.mp4
						// 一度これで短い動画を切り抜いてからそれを変換し直す

						String filename = FilenameUtils.getBaseName(selectedFile.getName());
						File temp = new File(selectedFile.getParentFile(), filename + "_" + filesize + "M_" + UUID.randomUUID().toString().split("-")[0] + ".mp4");

						final String cc = custom;

						if (!cc.equals("")) {
							runWithMainThread(() -> {
								button.setText("キャッシュファイルを作成中...");
							});

							ProcessManager.runCommand(new String[] { "ffmpeg.exe", "-i", selectedFile.getAbsolutePath(),
									"-ss", trimInfo.getStart(), "-t", trimInfo.getStringDuration(),
									"-c", "copy", temp.getAbsolutePath() }, new net.simplyrin.processmanager.Callback() {
								int videoTime = 0;
								public void line(String response) {
									if (response.trim().startsWith("Duration:")) {
										String time = response.trim().split(" ")[1].split(" ")[0];

										int videoTime = 0;

										Time parsedTime = parseTime(time);
										videoTime += parsedTime.totalSeconds();
										// System.out.println("Video Time: " + videoTime + "s");
										if (trimInfo.bitrate != 0 && trimInfo.duration != 0) {
											videoTime = (int) trimInfo.getDuration();
										}
										this.videoTime = videoTime;
									}

									if (response.startsWith("frame")) {
										String time = response.split("time=")[1].split(" ")[0];

										Time parsedTime = parseTime(time);
										int videoTime = parsedTime.totalSeconds();

										double current = (double) videoTime / this.videoTime * 100;

										runWithMainThread(() -> {
											String size;
											try {
												size = response.split("size=")[1].trim().split(" ")[0];
											} catch (Exception e) {
												size = response.split("Lsize=")[1].trim().split(" ")[0];
											}

											if (size.equals("0kB")) {
												button.setText("キャッシュ処理中...。");
											} else {
												button.setText("キャッシュ作成中: " + String.format("%.1f", current) + "% (" + size + ")");
											}
										});
									}
								}

								public void processEnded() {
								}
							}, false);
						}

						runWithMainThread(() -> {
							File output;
							if (cc.equals("")) {
								output = new File(selectedFile.getParentFile(), filename + "_" + filesize + "M.mp4");
							} else {
								output = new File(selectedFile.getParentFile(), filename + "_" + filesize + "M_" + trimInfo.getStart().replace(":", "") + "-" + trimInfo.getEnd().replace(":", "") + ".mp4");
							}
							if (output.exists()) {
								resetButton();
								buildAlert(AlertType.ERROR, "エラー！", "ファイルが既に存在します。", "この動画は既にエンコード済みの可能性があります。");
								return;
							}

							String command = "ffmpeg.exe -i \"" + (cc.equals("") ? selectedFile.getAbsolutePath() : temp.getAbsolutePath()) + "\" -rc cbr " /* + cc*/ +
									"-ab 96k -bf 2 -b:v " + bitrate + "k -maxrate " + (bitrate + 5) + "k -bufsize "
									+ ((int) bitrate) + "k \"" + output.getAbsolutePath() + "\"";
							latestOutput = output;

							// System.out.println("Exec: " + command);
							runCommand(command, secondCallback, true);
						});
					}
				}
			};

			this.runCommand("ffprobe.exe -hide_banner \"" + this.selectedFile.getAbsolutePath() + "\"", firstCallback, true);
			return;
		} else {
			this.buildAlert(AlertType.ERROR, "エラー", "エラーが発生しました。", "ファイルを選択してください。");
		}
	}

	private File latestOutput;

	@FXML
	private void checkOsl(ActionEvent event) {
		this.buildAlert(AlertType.INFORMATION, "Open Source Info", "ライセンス情報・詳しいライセンスの情報は、コンソールに出力しています。",
				"Apache, Commons-IO:\n"
				+ "  Apache License 2.0\n"
				+ "  https://github.com/apache/commons-io/blob/master/LICENSE.txt\n\n"
				+ "rzwitserloot, lombok\n"
				+ "  MIT License\n"
				+ "  https://github.com/rzwitserloot/lombok/blob/master/LICENSE\n\n"
				+ "google, gson\n"
				+ "  Apache License 2.0\n"
				+ "  https://github.com/google/gson/blob/master/LICENSE\n\n"
				+ "ffmpeg\n"
				+ "  GNU Lesser General Public License (LGPL) version 2.1\n"
				+ "  http://ffmpeg.org/legal.html\n\n"
				+ "SimplyRin, ProcessManager\n"
				+ "  MIT License\n"
				+ "  https://github.com/SimplyRin/ProcessManager/blob/master/LICENSE.md\n\n"
				+ "");
		OpenSourceInfo.print();
	}

	@FXML
	private void chooseFile(ActionEvent event) {
		if (this.ffmpeg()) {
			return;
		}

		if (this.ffprobe()) {
			return;
		}

		if (this.chooseButton.getText().equals("削除")) {
			this.selectedFile = null;

			this.chooseButton.setText("選択");
			this.fileName.setText("選択されていません。");
			return;
		}

		// System.out.println("CHOOSE");
		File file = this.openFileChooser("動画ファイルを選択");

		if (file == null) {
			return;
		}

		this.selectFile(file);
	}

	private static Controller controller;

	public static Controller getController() {
		return controller;
	}

	public void selectFile(File file) {
		if (this.selectedFile != null && this.selectedFile.equals(file)) {
			return;
		}

		String filename = FilenameUtils.getBaseName(file.getName());
		String extension = FilenameUtils.getExtension(file.getName());

		// System.out.println(filename + "." + extension);

		this.selectedFile = file;

		if (filename.length() >= 20) {
			filename = filename.substring(0, 20) + "..";
		}

		this.fileName.setText(filename + "." + extension);
		this.chooseButton.setText("削除");
	}

	private String start;
	private String end;
	private double startDouble = 0;
	private double endDouble = 0;

	private TrimInfo item() {
		this.startDouble = 0;
		this.endDouble = 0;

		Alert alert = new Alert(Alert.AlertType.INFORMATION);
		alert.setTitle("動画のトリミング");
		alert.setHeaderText("トリミングしない場合はそのまま \"OK\" を押してください。");

		final MediaPlayer mediaPlayer;
		try {
			mediaPlayer = new MediaPlayer(new Media(this.selectedFile.toURI().toURL().toString()));
		} catch (MalformedURLException e1) {
			e1.printStackTrace();
			return null;
		}
		mediaPlayer.setVolume(0.05);
		MediaView mediaView = new MediaView(mediaPlayer);
		mediaView.setFitHeight(480);
		mediaView.setFitHeight(360);

		GridPane gridPane = new GridPane();
		gridPane.setHgap(10);
		gridPane.setVgap(10);
		gridPane.setPadding(new Insets(20, 150, 10, 10));


		// ToolBar -- START
		ToolBar toolBar = new ToolBar();
		Button play = new Button("再生");
		play.setOnAction(event -> {
			mediaPlayer.play();
		});
		toolBar.getItems().add(play);
		Button pause = new Button("一時停止");
		pause.setOnAction(event -> {
			mediaPlayer.pause();
		});
		toolBar.getItems().add(pause);
		// toolBar.getItems().add(new Separator());
		//Button encode = new Button("エンコード");
		//encode.setOnAction(event -> {
		//	mediaPlayer.pause();
		//});
		// toolBar.getItems().add(encode);
		gridPane.add(toolBar, 1, 0);
		// ToolBar -- END


		// 開始位置 -- START
		ToolBar sPoint = new ToolBar();
		Button startPoint = new Button("開始位置に設定");
		Label sLabel = new Label("開始位置: ");
		startPoint.setOnAction(event -> {
			Duration duration = mediaPlayer.getCurrentTime();
			this.startDouble = duration.toSeconds();
			this.start = this.formatDuration(duration);
			sLabel.setText("開始位置: " + this.start);
		});
		sPoint.getItems().add(startPoint);
		sPoint.getItems().add(new Separator());
		sPoint.getItems().add(sLabel);
		gridPane.add(sPoint, 1, 1);
		// 開始位置 -- END

		// 開始位置 -- START
		ToolBar ePoint = new ToolBar();
		Button endPoint = new Button("停止位置に設定");
		Label eLabel = new Label("停止位置: ");
		endPoint.setOnAction(event -> {
			Duration duration = mediaPlayer.getCurrentTime();
			if (this.startDouble < duration.toSeconds()) {
				this.endDouble = duration.toSeconds();
				this.end = this.formatDuration(duration);
				eLabel.setText("停止位置: " + this.end);
			} else {
				this.buildAlert(AlertType.ERROR, "エラー！", "", "開始位置より前に停止位置を設定することはできません。");
			}
		});
		ePoint.getItems().add(endPoint);
		ePoint.getItems().add(new Separator());
		ePoint.getItems().add(eLabel);
		gridPane.add(ePoint, 1, 2);
		// 開始位置 -- END

		// Slidebar -- START
		Slider slider = new Slider();
		slider.maxProperty().bind(Bindings.createDoubleBinding(() -> mediaPlayer.getTotalDuration().toSeconds(), mediaPlayer.totalDurationProperty()));
		InvalidationListener sliderChangeListener = (o -> {
		    Duration seekTo = Duration.seconds(slider.getValue());
		    mediaPlayer.seek(seekTo);
		});
		slider.valueProperty().addListener(sliderChangeListener);
		gridPane.add(slider, 1, 3);
		// Slidebar -- END

		gridPane.add(mediaView, 1, 4);

		alert.getDialogPane().setContent(gridPane);

		mediaPlayer.currentTimeProperty().addListener(l -> {
			slider.valueProperty().removeListener(sliderChangeListener);
			Duration currentTime = mediaPlayer.getCurrentTime();
			int value = (int) currentTime.toSeconds();
			slider.setValue(value);
		    slider.valueProperty().addListener(sliderChangeListener);
		});

		alert.getDialogPane().setMinHeight(622);
		alert.getDialogPane().setMinWidth(681);

		alert.setOnShowing(e -> {
			mediaPlayer.play();
		});
		Optional<ButtonType> result = alert.showAndWait();
		if (result.get() == null) {
			return null;
		}

		int duration = 0;
		if (this.endDouble != 0 && this.startDouble != 0) {
			duration = (int) Math.ceil(this.endDouble - this.startDouble);
		}

		int bitrate = 0;
		if (duration != 0) {
			bitrate = (int) this.setTimeSize(duration, this.filesize);
		}

		// System.exit(0);
		mediaPlayer.pause();

		return new TrimInfo(this.start, this.end, duration, bitrate);
	}

	public String formatDuration(Duration duration) {
		long seconds = (long) duration.toSeconds();
		long absSeconds = Math.abs(seconds);
		String positive = String.format("%d:%02d:%02d", absSeconds / 3600, (absSeconds % 3600) / 60, absSeconds % 60);
		return seconds < 0 ? "-" + positive : positive;
	}

	@Getter
	@AllArgsConstructor
	public class TrimInfo {
		private String start;
		private String end;
		private int duration;
		private int bitrate;

		/**
		 * 開始が 10:00 で終了が 15:00 の場合、5:00 を返します。
		 */
		public String getStringDuration() {
			long absSeconds = Math.abs(this.duration);
			int hour = (int) absSeconds / 3600;
			int minute = (int) (absSeconds % 360) / 60;
			int second = (int) absSeconds % 60;

			// String value = hour + ":" + minute + ":" + second;;
			String value = "";

			boolean one = false;
			if (hour == 0) {
				value += "";
			} else {
				value += hour + ":";
				one = true;
			}

			if (minute == 0) {
				value += (one ? "00:" : "");
			} else if (minute <= 9) {
				value += (one ? "0" : "") + minute + ":";
			} else {
				value += minute + ":";
			}

			if (second == 0) {
				value += "00";
			} else if (second <= 9) {
				value += "0" + second;
			} else {
				value += second;
			}

			return value;
		}
	}

	private void buildAlert(Alert.AlertType alertyType, String title, String headerText, String content) {
		this.textField.clear();

		Stage primaryStage = (Stage) this.button.getScene().getWindow();

		Alert alert = new Alert(alertyType);
		Stage stage = (Stage) alert.getDialogPane().getScene().getWindow();

		try {
			stage.getIcons().add(primaryStage.getIcons().get(0));
		} catch (Exception e) {
		}

		alert.setTitle(title);
		alert.setHeaderText(headerText);
		if (content != null) {
			alert.setContentText(content);
		}
		alert.show();
	}

	private void resetButton() {
		this.runWithMainThread(() -> {
			this.button.setText("エンコード！");
			this.button.setDisable(false);
		});
	}

	private File openFileChooser(String title) {
		FileChooser fileChooser = new FileChooser();
		fileChooser.setTitle(title);

		return fileChooser.showOpenDialog(this.button.getScene().getWindow());
	}

	public String formatFileSize(long size) {
		String hrSize = null;

		double b = size;
		double k = size / 1024.0;
		double m = k / 1024.0;
		double g = m / 1024.0;
		double t = g / 1024.0;

		DecimalFormat decimalFormat = new DecimalFormat("0.00");

		if (t > 1) {
			hrSize = decimalFormat.format(t).concat(" TB");
		} else if (g > 1) {
			hrSize = decimalFormat.format(g).concat(" GB");
		} else if (m > 1) {
			hrSize = decimalFormat.format(m).concat(" MB");
		} else if (k > 1) {
			hrSize = decimalFormat.format(k).concat(" KB");
		} else {
			hrSize = decimalFormat.format(b).concat(" Bytes");
		}

		return hrSize;
	}

	private void runCommand(String command, Callback callback, boolean async) {
		System.out.println("Execute: " + command);
		final Process process;
		try {
			ProcessBuilder processBuilder = new ProcessBuilder(command.split(" "));
			processBuilder.redirectErrorStream(true);

			process = processBuilder.start();
		} catch (IOException e) {
			e.printStackTrace();
			this.buildAlert(AlertType.ERROR, "エラー", "不明なエラーが発生しました", this.getPrintStackTrace(e));

			return;
		}

		new Thread(new Runnable() {
			@Override
			public void run() {
				BufferedReader bufferedReader = new BufferedReader(new InputStreamReader(process.getInputStream()));
				String line = null;
				try {
					while ((line = bufferedReader.readLine()) != null) {
						callback.response(line);
					}
				} catch (Exception e) {
				}
			}
		}).start();

		if (async) {
			new Thread(() -> {
				try {
					process.waitFor();
				} catch (Exception e) {
					e.printStackTrace();
				}
				callback.response("taskEnded");
			}).start();
		} else {
			try {
				process.waitFor();
			} catch (Exception e) {
				e.printStackTrace();
			}
			callback.response("taskEnded");
		}
	}

	/**
	 * download ffmpeg and ffprobe
	 */
	private boolean ffmpeg() {
		this.questionnaire();



		File ffmpeg = new File("ffmpeg.exe");
		if (!ffmpeg.exists()) {
			new Thread(new Runnable() {
				@Override
				public void run() {
					try {
						FileUtils.copyInputStreamToFile(getInputStream("https://api.simplyrin.net/Files/DiscordVideo/ffmpeg.exe"), ffmpeg);
					} catch (Exception e) {
						e.printStackTrace();
						buildAlert(AlertType.ERROR, "Error", "ダウンロード失敗", "ffmpeg.exe のダウンロード中にエラーが発生しました。\n手動で ffmpeg.exe を設定し、使用してください");
					}
				}
			}).start();
		}

		File ffprobe = new File("ffprobe.exe");
		if (!ffprobe.exists()) {
			new Thread(new Runnable() {
				@Override
				public void run() {
					try {
						FileUtils.copyInputStreamToFile(getInputStream("https://api.simplyrin.net/Files/DiscordVideo/ffprobe.exe"), ffprobe);
					} catch (Exception e) {
						e.printStackTrace();
						buildAlert(AlertType.ERROR, "Error", "ダウンロード失敗", "ffprobe.exe のダウンロード中にエラーが発生しました。\n手動で ffprobe.exe を設定し、使用してください");
					}
				}
			}).start();
		}
		return false;
	}

	public InputStream getInputStream(String u) throws IOException {
		HttpsURLConnection connection = (HttpsURLConnection) new URL(u).openConnection();
		connection.addRequestProperty("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/87.0.4280.66 Safari/537.36");
		return connection.getInputStream();
	}

	private boolean questionnaire() {
		File folder = new File(System.getProperty("user.home") + "/AppData/Roaming/DiscordVideo");
		folder.mkdirs();

		File file = new File(folder, "enq.json");
		if (file.exists()) {
			JsonObject jsonObject = this.getFileAsJsonObject(file);
			return jsonObject.has("enq") ? jsonObject.get("enq").getAsBoolean() : false;
		}

		Alert alert = new Alert(AlertType.INFORMATION, "", ButtonType.YES, ButtonType.NO);
		alert.setTitle("フィードバックへの協力");
		alert.setHeaderText("匿名でのフィードバックにご協力ください");
		alert.setContentText("送信される内容には、動画のファイルサイズやビットレートが含まれます。\n匿名でのフィードバックに協力する場合は 'はい' を選択し、\n協力しない場合は、'いいえ' を選択してください。");
		Optional<ButtonType> result = alert.showAndWait();

		System.out.println("anke-to: " + result.get());

		boolean bool = false;
		if (result.get().equals(ButtonType.YES)) {
			bool = true;
		}


		try {
			FileWriter fileWriter = new FileWriter(file);
			fileWriter.write("{\"enq\":" + bool + "}");
			fileWriter.close();
		} catch (IOException e) {
			e.printStackTrace();
		}

		return bool;
	}

	/**
	 * checkAuth()
	 */
	private boolean ffprobe() {
		File file = new File("auth.json");
		file.delete();

		File folder = new File(System.getProperty("user.home") + "/AppData/Roaming/DiscordVideo");
		folder.mkdirs();

		boolean firstRegister = false;
		file = new File(folder, "auth.json");
		if (!file.exists()) {
			firstRegister = true;
		}

		if (firstRegister) {
			Dialog<Pair<String, String>> dialog = new Dialog<>();
			dialog.setTitle("認証が必要です。");
			dialog.setHeaderText("提供された情報を入力してください。");

			Image image = new Image(getClass().getResourceAsStream("/locked.png"));
			dialog.setGraphic(new ImageView(image));

			ButtonType loginButtonType = new ButtonType("ログイン", ButtonData.OK_DONE);
			dialog.getDialogPane().getButtonTypes().addAll(loginButtonType, ButtonType.CANCEL);

			GridPane grid = new GridPane();
			grid.setHgap(10);
			grid.setVgap(10);
			grid.setPadding(new Insets(20, 150, 10, 10));

			TextField username = new TextField();
			username.setPromptText("ユーザー名");
			PasswordField password = new PasswordField();
			password.setPromptText("パスワード");

			grid.add(new Label("ユーザー名:"), 0, 0);
			grid.add(username, 1, 0);
			grid.add(new Label("パスワード:"), 0, 1);
			grid.add(password, 1, 1);

			Node loginButton = dialog.getDialogPane().lookupButton(loginButtonType);
			loginButton.setDisable(true);
			username.textProperty().addListener((observable, oldValue, newValue) -> {
				loginButton.setDisable(newValue.trim().isEmpty());
			});

			dialog.getDialogPane().setContent(grid);
			Platform.runLater(() -> username.requestFocus());
			dialog.setResultConverter(dialogButton -> {
				if (dialogButton == loginButtonType) {
					return new Pair<>(username.getText(), password.getText());
				}
				return null;
			});

			Optional<Pair<String, String>> result = dialog.showAndWait();

			JsonObject jsonObject = new JsonObject();
			jsonObject.addProperty("id", result.get().getKey());
			jsonObject.addProperty("pass", result.get().getValue());

			try {
				BufferedWriter bufferedWriter = new BufferedWriter(new FileWriter(file));
				bufferedWriter.write("{\n" +
						"	\"id\": \"" + result.get().getKey() + "\",\n" +
						"	\"pass\": \"" + result.get().getValue() + "\"\n" +
						"}\n" +
						"");
				bufferedWriter.close();
			} catch (Exception e) {
			}
		}

		JsonObject jsonObject = this.getFileAsJsonObject(file);
		HttpClient httpClient = new HttpClient("https://api.simplyrin.net/App/DiscordVideo/login.php?nocache=" + UUID.randomUUID().toString());
		httpClient.setData("id=" + jsonObject.get("id").getAsString() + "&pass=" + jsonObject.get("pass").getAsString());
		jsonObject = new JsonParser().parse(httpClient.getResult()).getAsJsonObject();

		if (jsonObject.has("result") && jsonObject.get("result").getAsBoolean()) {
			return false;
		} else {
			file.delete();
			return this.ffprobe();
		}
	}

	/**
	 * getFileAsJsonObject
	 */
	private JsonObject getFileAsJsonObject(File file) {
		String json = "";
		try (BufferedReader bufferedReader = new BufferedReader(new FileReader(file))) {
			String text;
			while ((text = bufferedReader.readLine()) != null) {
				json += text;
			}
		} catch (Exception e) {
		}
		try {
			return new JsonParser().parse(json).getAsJsonObject();
		} catch (Exception e) {
			return new JsonObject();
		}
	}

	private void runWithMainThread(Runnable runnable) {
		Platform.runLater(runnable);
	}

	private Time parseTime(String time) {
		int hour = Integer.valueOf(time.split(":")[0]);
		int minute = Integer.valueOf(time.split(":")[1]);
		double second = Double.valueOf(time.split(":")[2].replace(",", ""));

		return new Time(hour, minute, second);
	}

	// HH:mm:ss
	public int formatToInt(String time) {
		int allTime = 0;

		int hour = Integer.valueOf(time.split(":")[0]);
		if (hour >= 1) {
			allTime += hour * 60 * 60;
		}
		int minute = Integer.valueOf(time.split(":")[1]);
		if (minute >= 1) {
			allTime += minute * 60;
		}
		int second = Integer.valueOf(time.split(":")[2]);
		if (second >= 1) {
			allTime += second;
		}

		return allTime;
	}

	@AllArgsConstructor
	private class Time {
		private int hour;
		private int minute;
		private double second;

		public int totalSeconds() {
			int time = 0;
			if (this.hour > 0) {
				time += this.hour * 60 * 60;
			}

			if (this.minute > 0) {
				time += this.minute * 60;
			}

			if (this.second > 0) {
				time += this.second;
			}
			return time;
		}
	}

	/**
	 * getPrintStackTrace()
	 */
	private String getPrintStackTrace(Exception exception) {
		StringWriter stringWriter = new StringWriter();
		PrintWriter printWriter = new PrintWriter(stringWriter);
		exception.printStackTrace(printWriter);
		printWriter.flush();
		return printWriter.toString();
	}

	/**
	 * calcBitrate
	 */
	private int setTimeSize(int time, int targetFileSize) {
		int bitrate = 8000;

		double tFS = (double) targetFileSize;

		double total;

		int capacity = 50;

		while (true) {
			total = (double) time * bitrate / 8 / 1000;

			if (total == capacity) {
				break;
			}

			if (total >= tFS) {
				bitrate = bitrate - 50;
			} else {
				break;
			}
		}

		// System.out.println("Bitrate: " + bitrate + " Kbps");
		// System.out.println("Time: " + time + " sec");
		// System.out.println("Total: " + total + " MB");

		bitrate -= capacity;

		return bitrate;
	}

	public interface Callback {
		void response(String response);
	}

}
