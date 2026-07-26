package net.simplyrin.discordvideo.test;

import java.io.File;
import java.io.IOException;

/**
 * Created by SimplyRin on 2020/07/01.
 *
 * Copyright (c) 2020 SimplyRin
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */
public class Explorer {

	public static void main(String[] args) {
		File file = new File("V:\\ShadowPlay\\Apex Legends\\Apex Legends 2020.03.03 - 15.23.42.08.DVR_50M_8M_00000-00155.mp4");
		System.out.println("Selected (" + file.exists() + "): " + file.getAbsolutePath());

		try {
			Runtime.getRuntime().exec("explorer.exe /select," + file.getAbsolutePath());
		} catch (IOException e) {
			e.printStackTrace();
		}
		// ProcessManager.runCommand(new String[] { "cmd", "/c", "start", "explorer", "/e,/select=\"" + file.getAbsolutePath() + "\"" }, new net.simplyrin.processmanager.Callback() {}, true);
	}

}
