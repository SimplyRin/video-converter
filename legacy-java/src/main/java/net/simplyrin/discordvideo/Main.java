package net.simplyrin.discordvideo;

import java.io.File;
import java.util.List;

import javafx.application.Application;
import javafx.event.EventHandler;
import javafx.fxml.FXMLLoader;
import javafx.scene.Parent;
import javafx.scene.Scene;
import javafx.scene.input.DragEvent;
import javafx.scene.input.Dragboard;
import javafx.stage.Stage;

/**
 * Created by SimplyRin on 2020/04/21.
 */
public class Main extends Application {

	public static void main(String[] args) {
		Application.launch(args);
	}

	@Override
	public void start(Stage stage) throws Exception {
		Parent parent = null;
		try {
			parent = FXMLLoader.load(this.getClass().getResource("/main.fxml"));
		} catch (Exception e) {
			e.printStackTrace();
			System.exit(0);
			return;
		}

		stage.setTitle("DiscordVideo Pre-4");
		stage.sizeToScene();
		stage.setResizable(false);
		Scene scene = new Scene(parent, 327, 138);
		EventHandler<DragEvent> eventHandler = new EventHandler<DragEvent>() {
			@Override
			public void handle(DragEvent event) {
				Dragboard dragboard = event.getDragboard();
				if (dragboard.hasFiles()) {
					List<File> files = dragboard.getFiles();
					if (files != null && !files.isEmpty()) {
						File file = files.get(0);
						Controller.getController().selectFile(file);
					}
				}
			}
		};
		scene.setOnDragOver(eventHandler);
		stage.setScene(scene);
		stage.show();
	}

}
